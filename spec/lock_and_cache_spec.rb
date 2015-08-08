require 'spec_helper'

class Foo
  include LockAndCache

  def initialize(id)
    @id = id
    @count = 0
    @count_exp = 0
  end

  def click
    lock_and_cache do
      @count += 1
    end
  end

  def click_exp
    lock_and_cache(expires: 1, foo: :bar) do
      @count_exp += 1
    end
  end

  def lock_and_cache_key
    @id
  end
end

require 'set'
$clicking = Set.new
class Bar
  include LockAndCache

  def initialize(id)
    @id = id
    @count = 0
  end

  def unsafe_click
    Thread.exclusive do
      # puts "clicking bar #{@id} - #{$clicking.to_a} - #{$clicking.include?(@id)} - #{@id == $clicking.to_a[0]}"
      raise "somebody already clicking Bar #{@id}" if $clicking.include?(@id)
      $clicking << @id
    end
    sleep 1
    @count += 1
    $clicking.delete @id
    @count
  end

  def click
    lock_and_cache do
      unsafe_click
    end
  end

  def slow_click
    lock_and_cache do
      sleep 1
    end
  end

  def lock_and_cache_key
    @id
  end
end

describe LockAndCache do
  before do
    LockAndCache.flush
  end

  it 'has a version number' do
    expect(LockAndCache::VERSION).not_to be nil
  end

  describe "caching" do
    let(:foo) { Foo.new(rand.to_s) }
    it "works" do
      expect(foo.click).to eq(1)
      expect(foo.click).to eq(1)
    end

    it "can be cleared" do
      expect(foo.click).to eq(1)
      foo.lock_and_cache_clear :click
      expect(foo.click).to eq(2)
    end

    it "can be expired" do
      expect(foo.click_exp).to eq(1)
      expect(foo.click_exp).to eq(1)
      sleep 2
      expect(foo.click_exp).to eq(2)
    end
  end

  describe "locking" do
    let(:bar) { Bar.new(rand.to_s) }

    it "it blows up normally (simple thread)" do
      a = Thread.new do
        bar.unsafe_click
      end
      b = Thread.new do
        bar.unsafe_click
      end
      expect do
        a.join
        b.join
      end.to raise_error(/somebody/)
    end

    it "it blows up (pre-existing thread pool, more reliable)" do
      pool = Thread.pool 2
      Thread::Pool.abort_on_exception = true
      expect do
        pool.process do
          bar.unsafe_click
        end
        pool.process do
          bar.unsafe_click
        end
        pool.shutdown
      end.to raise_error(/somebody/)
    end

    it "doesn't blow up if you lock it (simple thread)" do
      a = Thread.new do
        bar.click
      end
      b = Thread.new do
        bar.click
      end
      a.join
      b.join
    end

    it "doesn't blow up if you lock it (pre-existing thread pool, more reliable)" do
      pool = Thread.pool 2
      Thread::Pool.abort_on_exception = true
      pool.process do
        bar.click
      end
      pool.process do
        bar.click
      end
      pool.shutdown
    end

    it "can set a wait time" do
      pool = Thread.pool 2
      Thread::Pool.abort_on_exception = true
      begin
        old_max = LockAndCache.max_lock_wait
        LockAndCache.max_lock_wait = 0.5
        expect do
          pool.process do
            bar.slow_click
          end
          pool.process do
            bar.slow_click
          end
          pool.shutdown
        end.to raise_error(LockAndCache::TimeoutWaitingForLock)
      ensure
        LockAndCache.max_lock_wait = old_max
      end
    end

  end

end

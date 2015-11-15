require 'spec_helper'

class Foo
  include LockAndCache

  def initialize(id)
    @id = id
    @count = 0
    @count_exp = 0
    @click_single_hash_arg_as_options = 0
    @click_last_hash_as_options = 0
  end

  def click
    lock_and_cache do
      @count += 1
    end
  end

  def click_null
    lock_and_cache do
      nil
    end
  end

  def click_exp
    lock_and_cache(expires: 1) do
      @count_exp += 1
    end
  end

  # foo will be treated as option, so this is cacheable
  def click_single_hash_arg_as_options
    lock_and_cache(foo: rand, expires: 1) do
      @click_single_hash_arg_as_options += 1
    end
  end

  # foo will be treated as part of cache key, so this is uncacheable
  def click_last_hash_as_options
    lock_and_cache({foo: rand}, expires: 1) do
      @click_last_hash_as_options += 1
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

class Sleeper
  include LockAndCache

  def initialize
    @id = SecureRandom.hex
  end

  def poke
    lock_and_cache heartbeat_expires: 2 do
      sleep
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
      sleep 1.5
      expect(foo.click_exp).to eq(2)
    end

    it "can cache null" do
      expect(foo.click_null).to eq(nil)
      expect(foo.click_null).to eq(nil)
    end

    it "treats single hash arg as options" do
      expect(foo.click_single_hash_arg_as_options).to eq(1)
      expect(foo.click_single_hash_arg_as_options).to eq(1)
      sleep 1.1
      expect(foo.click_single_hash_arg_as_options).to eq(2)
    end

    it "treats last hash as options" do
      expect(foo.click_last_hash_as_options).to eq(1)
      expect(foo.click_last_hash_as_options).to eq(2) # it's uncacheable to prove we're not using as part of options
      expect(foo.click_last_hash_as_options).to eq(3)
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

    it 'unlocks if a process dies' do
      child = nil
      begin
        sleeper = Sleeper.new
        child = fork do
          sleeper.poke
        end
        sleep 0.1
        expect(sleeper.lock_and_cache_locked?(:poke)).to eq(true)  # the other process has it
        Process.kill 'KILL', child
        expect(sleeper.lock_and_cache_locked?(:poke)).to eq(true)  # the other (dead) process still has it
        sleep 2
        expect(sleeper.lock_and_cache_locked?(:poke)).to eq(false) # but now it should be cleared because no heartbeat
      ensure
        Process.kill('KILL', child) rescue Errno::ESRCH
      end
    end

    it "pays attention to heartbeats" do
      child = nil
      begin
        sleeper = Sleeper.new
        child = fork do
          sleeper.poke
        end
        sleep 0.1
        expect(sleeper.lock_and_cache_locked?(:poke)).to eq(true) # the other process has it
        sleep 2
        expect(sleeper.lock_and_cache_locked?(:poke)).to eq(true) # the other process still has it
        sleep 2
        expect(sleeper.lock_and_cache_locked?(:poke)).to eq(true) # the other process still has it
        sleep 2
        expect(sleeper.lock_and_cache_locked?(:poke)).to eq(true) # the other process still has it
      ensure
        Process.kill('TERM', child) rescue Errno::ESRCH
      end
    end

  end

  describe 'standalone' do
    it 'works like you expect' do
      count = 0
      expect(LockAndCache.lock_and_cache('hello') { count += 1 }).to eq(1)
      expect(count).to eq(1)
      expect(LockAndCache.lock_and_cache('hello') { count += 1 }).to eq(1)
      expect(count).to eq(1)
    end

    it 'allows expiry' do
      count = 0
      expect(LockAndCache.lock_and_cache('hello', expires: 1) { count += 1 }).to eq(1)
      expect(count).to eq(1)
      expect(LockAndCache.lock_and_cache('hello') { count += 1 }).to eq(1)
      expect(count).to eq(1)
      sleep 1.1
      expect(LockAndCache.lock_and_cache('hello') { count += 1 }).to eq(2)
      expect(count).to eq(2)
    end

    it "requires a key" do
      expect do
        LockAndCache.lock_and_cache do
          raise "this won't happen"
        end
      end.to raise_error(/need/)
    end

    it 'allows checking locks' do
      expect(LockAndCache.locked?(:sleeper)).to be_falsey
      t = Thread.new do
        LockAndCache.lock_and_cache(:sleeper) { sleep 1 }
      end
      sleep 0.2
      expect(LockAndCache.locked?(:sleeper)).to be_truthy
      t.join
    end

    it 'allows clearing' do
      count = 0
      expect(LockAndCache.lock_and_cache('hello') { count += 1 }).to eq(1)
      expect(count).to eq(1)
      LockAndCache.clear('hello')
      expect(LockAndCache.lock_and_cache('hello') { count += 1 }).to eq(2)
      expect(count).to eq(2)
    end

    it 'allows multi-part keys' do
      count = 0
      expect(LockAndCache.lock_and_cache(['hello', 1, { target: 'world' }]) { count += 1 }).to eq(1)
      expect(count).to eq(1)
      expect(LockAndCache.lock_and_cache(['hello', 1, { target: 'world' }]) { count += 1 }).to eq(1)
      expect(count).to eq(1)
    end
    
    it 'treats a single hash arg as a cache key (not as options)' do
      count = 0
      LockAndCache.lock_and_cache(hello: 'world', expires: 100) { count += 1 }
      expect(count).to eq(1)
      LockAndCache.lock_and_cache(hello: 'world', expires: 100) { count += 1 }
      expect(count).to eq(1)
      LockAndCache.lock_and_cache(hello: 'world', expires: 200) { count += 1 } # expires is being treated as part of cache key
      expect(count).to eq(2)
    end

    it "correctly identifies options hash" do
      count = 0
      LockAndCache.lock_and_cache({ hello: 'world' }, expires: 1, ignored: rand) { count += 1 }
      expect(count).to eq(1)
      LockAndCache.lock_and_cache({ hello: 'world' }, expires: 1, ignored: rand) { count += 1 } # expires is not being treated as part of cache key
      expect(count).to eq(1)
      sleep 1.1
      LockAndCache.lock_and_cache({ hello: 'world' }) { count += 1 }
      expect(count).to eq(2)
    end
  end

  describe "shorter expiry for null results" do
    it "optionally caches null for less time" do
      count = 0
      LockAndCache.lock_and_cache('hello', nil_expires: 1, expires: 2) { count += 1; nil }
      expect(count).to eq(1)
      LockAndCache.lock_and_cache('hello', nil_expires: 1, expires: 2) { count += 1; nil }
      expect(count).to eq(1)
      sleep 1.1 # this is enough to expire
      LockAndCache.lock_and_cache('hello', nil_expires: 1, expires: 2) { count += 1; nil }
      expect(count).to eq(2)
    end

    it "normally caches null for the same amount of time" do
      count = 0
      expect(LockAndCache.lock_and_cache('hello', expires: 1) { count += 1; nil }).to be_nil
      expect(count).to eq(1)
      expect(LockAndCache.lock_and_cache('hello', expires: 1) { count += 1; nil }).to be_nil
      expect(count).to eq(1)
      sleep 1.1
      expect(LockAndCache.lock_and_cache('hello', expires: 1) { count += 1; nil }).to be_nil
      expect(count).to eq(2)
    end

    it "caches non-null for normal time" do
      count = 0
      LockAndCache.lock_and_cache('hello', nil_expires: 1, expires: 2) { count += 1; true }
      expect(count).to eq(1)
      LockAndCache.lock_and_cache('hello', nil_expires: 1, expires: 2) { count += 1; true }
      expect(count).to eq(1)
      sleep 1.1
      LockAndCache.lock_and_cache('hello', nil_expires: 1, expires: 2) { count += 1; true }
      expect(count).to eq(1)
      sleep 1
      LockAndCache.lock_and_cache('hello', nil_expires: 1, expires: 2) { count += 1; true }
      expect(count).to eq(2)
    end
  end


end

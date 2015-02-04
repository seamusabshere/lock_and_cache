require 'spec_helper'

class Foo
  include LockAndCache

  def initialize(id)
    @id = id
    @count = 0
  end

  def click
    lock_and_cache(self) do
      @count += 1
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
    Thread.exclusive do
      $clicking.delete @id
    end
    @count
  end

  def click
    lock_and_cache(self) do
      unsafe_click
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
      foo.lock_and_cache_clear :click, foo
      expect(foo.click).to eq(2)
    end
  end

  describe "locking" do
    let(:bar) { Bar.new(rand.to_s) }
    it "it blows up normally" do
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

    it "doesn't blow up if you lock it" do
      a = Thread.new do
        bar.click
      end
      b = Thread.new do
        bar.click
      end
      a.join
      b.join
    end

  end

end

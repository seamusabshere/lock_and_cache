require 'lock_and_cache/version'

require 'hash_digest'
require 'active_record'
require 'with_advisory_lock'

module LockAndCache
  def LockAndCache.storage=(v)
    raise "only redis for now" unless v.class.to_s == 'Redis'
    @storage = v
  end

  def LockAndCache.storage
    @storage
  end

  def LockAndCache.flush
    storage.flushdb
  end

  class Key
    attr_reader :obj
    attr_reader :kaller

    def initialize(obj, kaller, parts)
      @obj = obj
      @kaller = kaller
      @_parts = parts
    end

    def digest
      @digest ||= ::HashDigest.digest3([obj_class_name, method_id] + parts)
    end

    def debug
      @debug ||= [obj_class_name, method_id] + parts
    end

    def parts
      @parts ||= @_parts.map do |v|
        case v
        when ::String, ::Symbol, ::Hash, ::Array
          v
        else
          v.respond_to?(:lock_and_cache_key) ? v.lock_and_cache_key : v.id
        end
      end
    end

    def method_id
      @method_id ||= begin
        kaller[0] =~ /in `(\w+)'/
        $1 or raise "couldn't get method_id from #{kaller[0]}"
      end
    end

    def obj_class_name
      @obj_class_name ||= (obj.class == ::Class) ? obj.name : obj.class.name
    end

  end

  def lock_and_cache(*key_parts)
    raise "need a block" unless block_given?
    debug = (ENV['LOCK_AND_CACHE_DEBUG'] == 'true')
    key = LockAndCache::Key.new self, caller, key_parts
    digest = key.digest
    storage = LockAndCache.storage
    Thread.exclusive { $stderr.puts "[lock_and_cache] A #{key.debug}" } if debug
    if storage.exists digest
      return ::Marshal.load(storage.get(digest))
    end
    Thread.exclusive { $stderr.puts "[lock_and_cache] B #{key.debug}" } if debug
    ActiveRecord::Base.with_advisory_lock(digest) do
      Thread.exclusive { $stderr.puts "[lock_and_cache] C #{key.debug}" } if debug
      if storage.exists digest
        ::Marshal.load storage.get(digest)
      else
        Thread.exclusive { $stderr.puts "[lock_and_cache] D #{key.debug}" } if debug
        memo = yield
        storage.set digest, ::Marshal.dump(memo)
        memo
      end
    end
  end
end

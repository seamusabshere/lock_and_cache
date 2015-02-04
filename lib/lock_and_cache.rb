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
    attr_reader :method_id

    def initialize(obj, method_id, parts)
      @obj = obj
      @method_id = method_id
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

    def obj_class_name
      @obj_class_name ||= (obj.class == ::Class) ? obj.name : obj.class.name
    end

  end

  def lock_and_cache_clear(method_id, *key_parts)
    debug = (ENV['LOCK_AND_CACHE_DEBUG'] == 'true')
    key = LockAndCache::Key.new self, method_id, key_parts
    Thread.exclusive { $stderr.puts "[lock_and_cache] clear #{key.debug}" } if debug
    digest = key.digest
    LockAndCache.storage.del digest
  end

  def lock_and_cache(*key_parts)
    raise "need a block" unless block_given?
    debug = (ENV['LOCK_AND_CACHE_DEBUG'] == 'true')
    caller[0] =~ /in `(\w+)'/
    method_id = $1 or raise "couldn't get method_id from #{kaller[0]}"
    key = LockAndCache::Key.new self, method_id, key_parts
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

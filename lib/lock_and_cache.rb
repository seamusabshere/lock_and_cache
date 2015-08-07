require 'lock_and_cache/version'
require 'redis'
require 'redlock'
require 'hash_digest'
require 'active_support'
require 'active_support/core_ext'

module LockAndCache
  DEFAULT_LOCK_EXPIRES = 60 * 60 * 24 * 3 * 1000 # 3 days in milliseconds
  DEFAULT_LOCK_SPIN = 0.1

  # @param redis_connection [Redis] A redis connection to be used for lock and cached value storage
  def LockAndCache.storage=(redis_connection)
    raise "only redis for now" unless redis_connection.class.to_s == 'Redis'
    @storage = redis_connection
    @lock_manager = Redlock::Client.new [redis_connection]
  end

  # @return [Redis] The redis connection used for lock and cached value storage
  def LockAndCache.storage
    @storage
  end

  # Flush LockAndCache's storage
  #
  # @note If you are sharing a redis database, it will clear it...
  def LockAndCache.flush
    storage.flushdb
  end

  # @param seconds [Numeric] Lock expiry in seconds.
  #
  # @note Can be overridden by putting `expires:` in your call to `#lock_and_cache`
  def LockAndCache.lock_expires=(seconds)
    @lock_expires = seconds.to_f * 1000
  end

  # @return [Numeric] Lock expiry in milliseconds.
  # @private
  def LockAndCache.lock_expires
    @lock_expires || DEFAULT_LOCK_EXPIRES
  end

  # @param seconds [Numeric] How long to wait before trying a lock again, in seconds
  #
  # @note Can be overridden by putting `lock_spin:` in your call to `#lock_and_cache`
  def LockAndCache.lock_spin=(seconds)
    @lock_spin = seconds.to_f
  end

  # @private
  def LockAndCache.lock_spin
    @lock_spin || DEFAULT_LOCK_SPIN
  end

  # @private
  def LockAndCache.lock_manager
    @lock_manager
  end

  # @private
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

  # Clear a cache given exactly the method and exactly the same arguments
  #
  # @note Does not unlock.
  def lock_and_cache_clear(method_id, *key_parts)
    debug = (ENV['LOCK_AND_CACHE_DEBUG'] == 'true')
    key = LockAndCache::Key.new self, method_id, key_parts
    Thread.exclusive { $stderr.puts "[lock_and_cache] clear #{key.debug}" } if debug
    digest = key.digest
    LockAndCache.storage.del digest
  end

  # Lock and cache a method given key parts.
  #
  # @param key_parts [*] Parts that you want to include in the lock and cache key
  #
  # @return The cached value (possibly newly calculated).
  def lock_and_cache(*key_parts)
    raise "need a block" unless block_given?
    debug = (ENV['LOCK_AND_CACHE_DEBUG'] == 'true')
    caller[0] =~ /in `(\w+)'/
    method_id = $1 or raise "couldn't get method_id from #{kaller[0]}"
    options = key_parts.last.is_a?(Hash) ? key_parts.pop.stringify_keys : {}
    expires = options['expires']
    lock_expires = options.fetch 'lock_expires', LockAndCache.lock_expires
    lock_spin = options.fetch 'lock_spin', LockAndCache.lock_spin
    key = LockAndCache::Key.new self, method_id, key_parts
    digest = key.digest
    storage = LockAndCache.storage
    Thread.exclusive { $stderr.puts "[lock_and_cache] A #{key.debug}" } if debug
    if storage.exists digest
      return ::Marshal.load(storage.get(digest))
    end
    Thread.exclusive { $stderr.puts "[lock_and_cache] B #{key.debug}" } if debug
    retval = nil
    lock_manager = LockAndCache.lock_manager
    lock_digest = 'lock/' + digest
    lock_info = nil
    begin
      until lock_info = lock_manager.lock(lock_digest, lock_expires)
        sleep lock_spin
      end
      Thread.exclusive { $stderr.puts "[lock_and_cache] C #{key.debug}" } if debug
      if storage.exists digest
        retval = ::Marshal.load storage.get(digest)
      else
        Thread.exclusive { $stderr.puts "[lock_and_cache] D #{key.debug}" } if debug
        retval = yield
        if expires
          storage.setex digest, expires, ::Marshal.dump(retval)
        else
          storage.set digest, ::Marshal.dump(retval)
        end
      end
    ensure
      lock_manager.unlock lock_info
    end
    retval
  end
end

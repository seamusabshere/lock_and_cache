require 'lock_and_cache/version'
require 'timeout'
require 'digest/md5'
require 'base64'
require 'zlib'
require 'redis'
require 'redlock'
require 'active_support'
require 'active_support/core_ext'

# Lock and cache methods using redis!
#
# I bet you're caching, but are you locking?
module LockAndCache
  DEFAULT_LOCK_EXPIRES = 60 * 60 * 24 * 1 * 1000 # 1 day in milliseconds
  DEFAULT_LOCK_SPIN = 0.1
  DEFAULT_MAX_LOCK_WAIT = 60 * 60 * 24 # 1 day in seconds

  class TimeoutWaitingForLock < StandardError; end

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

  # @param seconds [Numeric] Maximum wait time to get a lock
  #
  # @note Can be overridden by putting `max_lock_wait:` in your call to `#lock_and_cache`
  def LockAndCache.max_lock_wait=(seconds)
    @max_lock_wait = seconds.to_f
  end

  # @private
  def LockAndCache.max_lock_wait
    @max_lock_wait || DEFAULT_MAX_LOCK_WAIT
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
      @method_id = method_id.to_sym
      @_parts = parts
    end

    # A (non-cryptographic) digest of the key parts for use as the cache key
    def digest
      @digest ||= ::Zlib::Deflate.deflate(::Marshal.dump(key), ::Zlib::BEST_SPEED)
    end

    # A (non-cryptographic) digest of the key parts for use as the lock key
    def lock_digest
      @lock_digest ||= 'lock/' + digest
    end

    # A human-readable representation of the key parts
    def key
      @key ||= [obj_class_name, method_id, parts]
    end

    alias debug key

    # An array of the parts we use for the key
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

    # An object (or its class's) name
    def obj_class_name
      @obj_class_name ||= (obj.class == ::Class) ? obj.name : obj.class.name
    end

  end

  # Clear a lock and cache given exactly the method and exactly the same arguments
  def lock_and_cache_clear(method_id, *key_parts)
    debug = (ENV['LOCK_AND_CACHE_DEBUG'] == 'true')
    key = LockAndCache::Key.new self, method_id, key_parts
    Thread.exclusive { $stderr.puts "[lock_and_cache] clear #{key.debug} #{Base64.encode64(key.digest).strip} #{Digest::MD5.hexdigest key.digest}" } if debug
    LockAndCache.storage.del key.digest
    LockAndCache.storage.del key.lock_digest
  end

  # Lock and cache a method given key parts.
  #
  # @param key_parts [*] Parts that you want to include in the lock and cache key
  #
  # @return The cached value (possibly newly calculated).
  def lock_and_cache(*key_parts)
    raise "need a block" unless block_given?
    debug = (ENV['LOCK_AND_CACHE_DEBUG'] == 'true')
    caller[0] =~ /in `([^']+)'/
    method_id = $1 or raise "couldn't get method_id from #{caller[0]}"
    options = key_parts.last.is_a?(Hash) ? key_parts.pop.stringify_keys : {}
    expires = options['expires']
    lock_expires = options.fetch 'lock_expires', LockAndCache.lock_expires
    lock_spin = options.fetch 'lock_spin', LockAndCache.lock_spin
    max_lock_wait = options.fetch 'max_lock_wait', LockAndCache.max_lock_wait
    key = LockAndCache::Key.new self, method_id, key_parts
    digest = key.digest
    storage = LockAndCache.storage or raise("must set LockAndCache.storage=[Redis]")
    Thread.exclusive { $stderr.puts "[lock_and_cache] A1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::MD5.hexdigest digest}" } if debug
    if storage.exists digest
      return ::Marshal.load(storage.get(digest))
    end
    Thread.exclusive { $stderr.puts "[lock_and_cache] B1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::MD5.hexdigest digest}" } if debug
    retval = nil
    lock_manager = LockAndCache.lock_manager
    lock_digest = key.lock_digest
    lock_info = nil
    begin
      Timeout.timeout(max_lock_wait, TimeoutWaitingForLock) do
        until lock_info = lock_manager.lock(lock_digest, lock_expires)
          Thread.exclusive { $stderr.puts "[lock_and_cache] C1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::MD5.hexdigest digest}" } if debug
          sleep lock_spin
        end
      end
      Thread.exclusive { $stderr.puts "[lock_and_cache] D1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::MD5.hexdigest digest}" } if debug
      if storage.exists digest
        Thread.exclusive { $stderr.puts "[lock_and_cache] E1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::MD5.hexdigest digest}" } if debug
        retval = ::Marshal.load storage.get(digest)
      else
        Thread.exclusive { $stderr.puts "[lock_and_cache] F1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::MD5.hexdigest digest}" } if debug
        retval = yield
        if expires
          storage.setex digest, expires, ::Marshal.dump(retval)
        else
          storage.set digest, ::Marshal.dump(retval)
        end
      end
    ensure
      lock_manager.unlock lock_info if lock_info
    end
    retval
  end
end

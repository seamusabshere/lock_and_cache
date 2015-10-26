require 'timeout'
require 'digest/sha1'
require 'base64'
require 'redis'
require 'redlock'
require 'active_support'
require 'active_support/core_ext'

require_relative 'lock_and_cache/version'
require_relative 'lock_and_cache/action'
require_relative 'lock_and_cache/key'

# Lock and cache methods using redis!
#
# I bet you're caching, but are you locking?
module LockAndCache
  DEFAULT_MAX_LOCK_WAIT = 60 * 60 * 24 # 1 day in seconds

  # @private
  LOCK_HEARTBEAT_EXPIRES = 2

  # @private
  LOCK_HEARTBEAT_PERIOD = 1

  class TimeoutWaitingForLock < StandardError; end

  # @param redis_connection [Redis] A redis connection to be used for lock and cached value storage
  def LockAndCache.storage=(redis_connection)
    raise "only redis for now" unless redis_connection.class.to_s == 'Redis'
    @storage = redis_connection
    @lock_manager = Redlock::Client.new [redis_connection], retry_count: 1
  end

  # @return [Redis] The redis connection used for lock and cached value storage
  def LockAndCache.storage
    @storage
  end

  # Flush LockAndCache's storage.
  #
  # @note If you are sharing a redis database, it will clear it...
  #
  # @note If you want to clear a single key, try `LockAndCache.clear(key)` (standalone mode) or `#lock_and_cache_clear(method_id, *key_parts)` in context mode.
  def LockAndCache.flush
    storage.flushdb
  end

  # Lock and cache based on a key.
  #
  # @param key_parts [*] Parts that should be used to construct a key.
  #
  # @note Standalone mode. See also "context mode," where you mix LockAndCache into a class and call it from within its methods.
  #
  # @note A single hash arg is treated as a cached key. `LockAndCache.lock_and_cache(foo: :bar, expires: 100)` will be treated as a cache key of `foo: :bar, expires: 100` (which is probably wrong!!!). `LockAndCache.lock_and_cache({foo: :bar}, expires: 100)` will be treated as a cache key of `foo: :bar` and options `expires: 100`. This is the opposite of context mode and is true because we don't have any context to set the cache key from otherwise.
  def LockAndCache.lock_and_cache(*key_parts_and_options, &blk)
    options = (key_parts_and_options.last.is_a?(Hash) && key_parts_and_options.length > 1) ? key_parts_and_options.pop : {}
    raise "need a cache key" unless key_parts_and_options.length > 0
    key = LockAndCache::Key.new key_parts_and_options
    action = LockAndCache::Action.new key, options, blk
    action.perform
  end

  # Clear a single key
  #
  # @note Standalone mode. See also "context mode," where you mix LockAndCache into a class and call it from within its methods.
  def LockAndCache.clear(*key_parts)
    key = LockAndCache::Key.new key_parts
    key.clear
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

  # Check if a method is locked on an object.
  #
  # @note Subject mode - this is expected to be called on an object that has LockAndCache mixed in. See also standalone mode.
  def lock_and_cache_locked?(method_id, *key_parts)
    key = LockAndCache::Key.new key_parts, context: self, method_id: method_id
    key.locked?
  end

  # Clear a lock and cache given exactly the method and exactly the same arguments
  #
  # @note Subject mode - this is expected to be called on an object that has LockAndCache mixed in. See also standalone mode.
  def lock_and_cache_clear(method_id, *key_parts)
    key = LockAndCache::Key.new key_parts, context: self, method_id: method_id
    key.clear
  end

  # Lock and cache a method given key parts.
  #
  # This is the defining characteristic of context mode: the cache key will automatically include the class name of the object calling it (the context!) and the name of the method it is called from.
  #
  # @param key_parts_and_options [*] Parts that you want to include in the lock and cache key. If the last element is a Hash, it will be treated as options.
  #
  # @return The cached value (possibly newly calculated).
  #
  # @note Subject mode - this is expected to be called on an object that has LockAndCache mixed in. See also standalone mode.
  #
  # @note A single hash arg is treated as an options hash. `lock_and_cache(expires: 100)` will be treated as options `expires: 100`. This is the opposite of standalone mode and true because we want to support people constructing cache keys from the context (context) PLUS an arbitrary hash of stuff.
  def lock_and_cache(*key_parts_and_options, &blk)
    options = key_parts_and_options.last.is_a?(Hash) ? key_parts_and_options.pop : {}
    key = LockAndCache::Key.new key_parts_and_options, context: self, caller: caller
    action = LockAndCache::Action.new key, options, blk
    action.perform
  end
end

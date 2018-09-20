$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'lock_and_cache'

require 'timeout'

require 'redis'
LockAndCache.lock_storage = Redis.new db: 3
LockAndCache.cache_storage = Redis.new db: 4

require 'thread/pool'

require 'pry'

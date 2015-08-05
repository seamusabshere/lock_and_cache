$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'lock_and_cache'

require 'redis'
LockAndCache.storage = Redis.new

require 'thread/pool'

require 'pry'

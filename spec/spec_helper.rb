$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'lock_and_cache'
require 'thread/pool'

ActiveRecord::Base.establish_connection adapter: 'postgresql', database: 'lock_and_cache_test'

require 'pry'

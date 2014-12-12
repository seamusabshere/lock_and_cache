require 'lock_and_cache/version'

require 'hash_digest'
require 'cache_method'
require 'active_record'
require 'with_advisory_lock'

module LockAndCache
  # only for instance methods
  def lock_and_cache(method_id)
    unlocked_method_id = "_lock_and_cache_unlocked_#{method_id}"
    alias_method unlocked_method_id, method_id

    define_method method_id do |*args|
      debug = (ENV['LOCK_AND_CACHE_DEBUG'] == 'true')
      lock_key = [self.class.name, method_id, HashDigest.digest3([as_cache_key]+args)].join('/')
      debug_lock_key = [self.class.name, method_id, [as_cache_key]+args].join('/') if debug
      Thread.exclusive { $stderr.puts "[lock_and_cache] A #{debug_lock_key}" } if debug
      if cache_method_cached?(method_id, args)
        return send(method_id, *args) # which will be the cached version
      end
      Thread.exclusive { $stderr.puts "[lock_and_cache] B #{debug_lock_key}" } if debug
      ActiveRecord::Base.with_advisory_lock(lock_key) do
        Thread.exclusive { $stderr.puts "[lock_and_cache] C #{debug_lock_key}" } if debug
        if cache_method_cached?(method_id, args)
          send method_id, *args # which will be the cached version
        else
          Thread.exclusive { $stderr.puts "[lock_and_cache] D #{debug_lock_key}" } if debug
          send unlocked_method_id, *args
        end
      end
    end

    cache_method method_id
  end
end

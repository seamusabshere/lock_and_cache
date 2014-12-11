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
      lock_key = [self.class.name, method_id, HashDigest.digest3([as_cache_key]+args)].join('/')
      ActiveRecord::Base.with_advisory_lock(lock_key) do
        if cache_method_cached?(method_id, args)
          send method_id, *args # which will be the cached version
        else
          send unlocked_method_id
        end
      end
    end

    cache_method method_id
  end
end

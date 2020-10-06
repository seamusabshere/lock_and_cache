module LockAndCache
  # @private
  class Action
    ERROR_MAGIC_KEY = :lock_and_cache_error

    attr_reader :key
    attr_reader :options
    attr_reader :blk

    def initialize(key, options, blk)
      raise "need a block" unless blk
      @key = key
      @options = options.stringify_keys
      @blk = blk
    end

    def expires
      return @expires if defined?(@expires)
      @expires = options.has_key?('expires') ? options['expires'].to_f.round : nil
    end

    def nil_expires
      return @nil_expires if defined?(@nil_expires)
      @nil_expires = options.has_key?('nil_expires') ? options['nil_expires'].to_f.round : nil
    end

    def digest
      @digest ||= key.digest
    end

    def lock_digest
      @lock_digest ||= key.lock_digest
    end

    def lock_storage
      @lock_storage ||= LockAndCache.lock_storage or raise("must set LockAndCache.lock_storage=[Redis]")
    end

    def cache_storage
      @cache_storage ||= LockAndCache.cache_storage or raise("must set LockAndCache.cache_storage=[Redis]")
    end

    def load_existing(existing)
      v = ::Marshal.load(existing)
      if v.is_a?(::Hash) and (founderr = v[ERROR_MAGIC_KEY])
        raise "Another LockAndCache process raised #{founderr}"
      else
        v
      end
    end

    def perform
      max_lock_wait = options.fetch 'max_lock_wait', LockAndCache.max_lock_wait
      heartbeat_expires = options.fetch('heartbeat_expires', LockAndCache.heartbeat_expires).to_f.ceil
      raise "heartbeat_expires must be >= 2 seconds" unless heartbeat_expires >= 2
      heartbeat_frequency = (heartbeat_expires / 2).ceil
      LockAndCache.logger.debug { "[lock_and_cache] A1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
      if cache_storage.exists?(digest) and (existing = cache_storage.get(digest)).is_a?(String)
        return load_existing(existing)
      end
      LockAndCache.logger.debug { "[lock_and_cache] B1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
      retval = nil
      lock_secret = SecureRandom.hex 16
      acquired = false
      begin
        Timeout.timeout(max_lock_wait, TimeoutWaitingForLock) do
          until lock_storage.set(lock_digest, lock_secret, nx: true, ex: heartbeat_expires)
            LockAndCache.logger.debug { "[lock_and_cache] C1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
            sleep rand
          end
          acquired = true
        end
        LockAndCache.logger.debug { "[lock_and_cache] D1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
        if cache_storage.exists?(digest) and (existing = cache_storage.get(digest)).is_a?(String)
          LockAndCache.logger.debug { "[lock_and_cache] E1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
          retval = load_existing existing
        end
        unless retval
          LockAndCache.logger.debug { "[lock_and_cache] F1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
          done = false
          begin
            lock_extender = Thread.new do
              loop do
                LockAndCache.logger.debug { "[lock_and_cache] heartbeat1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
                break if done
                sleep heartbeat_frequency
                break if done
                LockAndCache.logger.debug { "[lock_and_cache] heartbeat2 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
                # FIXME use lua to check the value
                raise "unexpectedly lost lock for #{key.debug}" unless lock_storage.get(lock_digest) == lock_secret
                lock_storage.set lock_digest, lock_secret, xx: true, ex: heartbeat_expires
              end
            end
            begin
              retval = blk.call
              retval.nil? ? set_nil : set_non_nil(retval)
            rescue
              set_error $!
              raise
            end
          ensure
            done = true
            lock_extender.join if lock_extender.status.nil?
          end
        end
      ensure
        lock_storage.del lock_digest if acquired
      end
      retval
    end

    def set_error(exception)
      cache_storage.set digest, ::Marshal.dump(ERROR_MAGIC_KEY => exception.message), ex: 1
    end

    NIL = Marshal.dump nil
    def set_nil
      if nil_expires
        cache_storage.set digest, NIL, ex: nil_expires
      elsif expires
        cache_storage.set digest, NIL, ex: expires
      else
        cache_storage.set digest, NIL
      end
    end

    def set_non_nil(retval)
      raise "expected not null #{retval.inspect}" if retval.nil?
      if expires
        cache_storage.set digest, ::Marshal.dump(retval), ex: expires
      else
        cache_storage.set digest, ::Marshal.dump(retval)
      end
    end
  end
end

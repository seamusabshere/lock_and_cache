module LockAndCache
  # @private
  class Action
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

    def storage
      @storage ||= LockAndCache.storage or raise("must set LockAndCache.storage=[Redis]")
    end

    def perform
      max_lock_wait = options.fetch 'max_lock_wait', LockAndCache.max_lock_wait
      heartbeat_expires = options.fetch('heartbeat_expires', LockAndCache.heartbeat_expires).to_f.ceil
      raise "heartbeat_expires must be >= 2 seconds" unless heartbeat_expires >= 2
      heartbeat_frequency = (heartbeat_expires / 2).ceil
      LockAndCache.logger.debug { "[lock_and_cache] A1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
      if storage.exists(digest) and (existing = storage.get(digest)).is_a?(String)
        return ::Marshal.load(existing)
      end
      LockAndCache.logger.debug { "[lock_and_cache] B1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
      retval = nil
      lock_secret = SecureRandom.hex 16
      acquired = false
      begin
        Timeout.timeout(max_lock_wait, TimeoutWaitingForLock) do
          until storage.set(lock_digest, lock_secret, nx: true, ex: heartbeat_expires)
            LockAndCache.logger.debug { "[lock_and_cache] C1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
            sleep rand
          end
          acquired = true
        end
        LockAndCache.logger.debug { "[lock_and_cache] D1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
        if storage.exists(digest) and (existing = storage.get(digest)).is_a?(String)
          LockAndCache.logger.debug { "[lock_and_cache] E1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
          retval = ::Marshal.load existing
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
                raise "unexpectedly lost lock for #{key.debug}" unless storage.get(lock_digest) == lock_secret
                storage.set lock_digest, lock_secret, xx: true, ex: heartbeat_expires
              end
            end
            retval = blk.call
            retval.nil? ? set_nil : set_non_nil(retval)
          ensure
            done = true
            lock_extender.join if lock_extender.status.nil?
          end
        end
      ensure
        storage.del lock_digest if acquired
      end
      retval
    end

    NIL = Marshal.dump nil
    def set_nil
      if nil_expires
        storage.setex digest, nil_expires, NIL
      elsif expires
        storage.setex digest, expires, NIL
      else
        storage.set digest, NIL
      end
    end

    def set_non_nil(retval)
      raise "expected not null #{retval.inspect}" if retval.nil?
      if expires
        storage.setex digest, expires, ::Marshal.dump(retval)
      else
        storage.set digest, ::Marshal.dump(retval)
      end
    end
  end
end

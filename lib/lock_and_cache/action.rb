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
      options['expires']
    end

    def nil_expires
      options['nil_expires']
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
      debug = (ENV['LOCK_AND_CACHE_DEBUG'] == 'true')
      max_lock_wait = options.fetch 'max_lock_wait', LockAndCache.max_lock_wait
      heartbeat_expires = options.fetch('heartbeat_expires', LockAndCache.heartbeat_expires).to_f.ceil
      raise "heartbeat_expires must be >= 2 seconds" unless heartbeat_expires >= 2
      heartbeat_frequency = (heartbeat_expires / 2).ceil
      Thread.exclusive { $stderr.puts "[lock_and_cache] A1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" } if debug
      if storage.exists(digest) and (existing = storage.get(digest)).is_a?(String)
        return ::Marshal.load(existing)
      end
      Thread.exclusive { $stderr.puts "[lock_and_cache] B1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" } if debug
      retval = nil
      lock_manager = LockAndCache.lock_manager
      lock_info = nil
      begin
        Timeout.timeout(max_lock_wait, TimeoutWaitingForLock) do
          until lock_info = lock_manager.lock(lock_digest, heartbeat_expires*1000)
            Thread.exclusive { $stderr.puts "[lock_and_cache] C1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" } if debug
            sleep rand
          end
        end
        Thread.exclusive { $stderr.puts "[lock_and_cache] D1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" } if debug
        if storage.exists(digest) and (existing = storage.get(digest)).is_a?(String)
          Thread.exclusive { $stderr.puts "[lock_and_cache] E1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" } if debug
          retval = ::Marshal.load existing
        end
        unless retval
          Thread.exclusive { $stderr.puts "[lock_and_cache] F1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" } if debug
          done = false
          begin
            lock_extender = Thread.new do
              loop do
                Thread.exclusive { $stderr.puts "[lock_and_cache] heartbeat1 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" } if debug
                break if done
                sleep heartbeat_frequency
                break if done
                Thread.exclusive { $stderr.puts "[lock_and_cache] heartbeat2 #{key.debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" } if debug
                lock_manager.lock lock_digest, heartbeat_expires*1000, extend: lock_info
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
        lock_manager.unlock lock_info if lock_info
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

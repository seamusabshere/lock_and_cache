module LockAndCache
  # @private
  class Key
    class << self
      # @private
      #
      # Extract the method id from a method's caller array.
      def extract_method_id_from_caller(kaller)
        kaller[0] =~ METHOD_NAME_IN_CALLER
        raise "couldn't get method_id from #{kaller[0]}" unless $1
        $1.to_sym
      end

      # @private
      #
      # Get a context object's class name, which is its own name if it's an object.
      def extract_class_name(context)
        (context.class == ::Class) ? context.name : context.class.name
      end

      # @private
      #
      # Extract id from context. Calls #lock_and_cache_key if available, otherwise #id
      def extract_context_id(context)
        if context.class == ::Class
          nil
        elsif context.respond_to?(:lock_and_cache_key)
          context.lock_and_cache_key
        elsif context.respond_to?(:id)
          context.id
        else
          raise "#{context} must respond to #lock_and_cache_key or #id"
        end
      end
    end

    METHOD_NAME_IN_CALLER = /in `([^']+)'/

    attr_reader :context
    attr_reader :method_id

    def initialize(parts, options = {})
      @_parts = parts
      @context = options[:context]
      @method_id = if options.has_key?(:method_id)
        options[:method_id]
      elsif options.has_key?(:caller)
        Key.extract_method_id_from_caller options[:caller]
      elsif context
        raise "supposed to call context with method_id or caller"
      end
    end

    # A (non-cryptographic) digest of the key parts for use as the cache key
    def digest
      @digest ||= ::Digest::SHA1.hexdigest ::Marshal.dump(key)
    end

    # A (non-cryptographic) digest of the key parts for use as the lock key
    def lock_digest
      @lock_digest ||= 'lock/' + digest
    end

    # A human-readable representation of the key parts
    def key
      @key ||= if context
        [class_name, context_id, method_id, parts].compact
      else
        parts
      end
    end

    def locked?
      LockAndCache.storage.exists lock_digest
    end

    def clear
      LockAndCache::LOG_MUTEX.synchronize { $stderr.puts "[lock_and_cache] clear #{debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" } if ENV['LOCK_AND_CACHE_DEBUG'] == 'true'
      storage = LockAndCache.storage
      storage.del digest
      storage.del lock_digest
    end

    alias debug key

    def context_id
      @context_id ||= Key.extract_context_id context
    end

    def class_name
      @class_name ||= Key.extract_class_name context
    end

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
  end
end

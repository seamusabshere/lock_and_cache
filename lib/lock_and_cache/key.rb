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
      # Recursively extract id from obj. Calls #lock_and_cache_key if available, otherwise #id
      def extract_obj_id(obj)
        if obj.is_a?(::String) or obj.is_a?(::Symbol) or obj.is_a?(::Numeric)
          obj
        elsif obj.respond_to?(:lock_and_cache_key)
          obj.lock_and_cache_key
        elsif obj.respond_to?(:id)
          obj.id
        elsif obj.respond_to?(:map)
          obj.map { |objj| extract_obj_id objj }
        else
          raise "#{obj.inspect} must respond to #lock_and_cache_key or #id"
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
      return @context_id if defined?(@context_id)
      @context_id = if context.class == ::Class
        nil
      else
        Key.extract_obj_id context
      end
    end

    def class_name
      @class_name ||= Key.extract_class_name context
    end

    # An array of the parts we use for the key
    def parts
      @parts ||= Key.extract_obj_id @_parts
    end
  end
end

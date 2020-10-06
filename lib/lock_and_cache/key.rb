require 'date'

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
        klass = obj.class
        if ALLOWED_IN_KEYS.include?(klass)
          obj
        elsif DATE.include?(klass)
          obj.to_s
        elsif obj.respond_to?(:lock_and_cache_key)
          extract_obj_id obj.lock_and_cache_key
        elsif obj.respond_to?(:id)
          extract_obj_id obj.id
        elsif obj.respond_to?(:map)
          obj.map { |objj| extract_obj_id objj }
        else
          raise "#{obj.inspect} must respond to #lock_and_cache_key or #id"
        end
      end
    end

    ALLOWED_IN_KEYS = [
      ::String,
      ::Symbol,
      ::Numeric,
      ::TrueClass,
      ::FalseClass,
      ::NilClass,
      ::Integer,
      ::Float,
    ].to_set
    parts = ::RUBY_VERSION.split('.').map(&:to_i)
    unless parts[0] >= 2 and parts[1] >= 4
      ALLOWED_IN_KEYS << ::Fixnum
      ALLOWED_IN_KEYS << ::Bignum  
    end
    DATE = [
      ::Date,
      ::DateTime,
      ::Time,
    ].to_set
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
      LockAndCache.lock_storage.exists? lock_digest
    end

    def cached?
      LockAndCache.cache_storage.exists? digest
    end

    def clear
      LockAndCache.logger.debug { "[lock_and_cache] clear #{debug} #{Base64.encode64(digest).strip} #{Digest::SHA1.hexdigest digest}" }
      LockAndCache.cache_storage.del digest
      LockAndCache.lock_storage.del lock_digest
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

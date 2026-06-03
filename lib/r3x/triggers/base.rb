module R3x
  module Triggers
    class Base
      include Dsl::Validatable

      attr_reader :type, :options

      def initialize(type, **options)
        @type = type
        @options = options
      end

      def cron_schedulable?
        false
      end

      def manual?
        type == :manual
      end

      def unique_key
        # Generate unique key from type + sorted options hash
        key_json = MultiJSON.generate(options.sort.to_h)
        "#{type}:#{Digest::SHA256.hexdigest(key_json)[0..15]}"
      end
    end
  end
end

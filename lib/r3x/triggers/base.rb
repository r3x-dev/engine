# frozen_string_literal: true

module R3x
  module Triggers
    class Base
      include Dsl::Validatable

      validates_with Validators::TriggerKey

      attr_reader :type, :options, :key

      def initialize(type, key: nil, **options)
        @type = type
        @options = options
        @key = key.is_a?(String) || key.is_a?(Symbol) ? key.to_s.dup.freeze : key
      end

      def cron_schedulable?
        false
      end

      def manual?
        type == :manual
      end

      def unique_key
        return "#{type}:#{key}" unless key.nil?

        # Generate unique key from type + sorted options hash
        key_json = MultiJSON.generate(options.sort.to_h)
        "#{type}:#{Digest::SHA256.hexdigest(key_json)[0..15]}"
      end
    end
  end
end

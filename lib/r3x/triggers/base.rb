module R3x
  module Triggers
    class Base
      include Dsl::Validatable

      attr_reader :type, :options

      def initialize(type, **options)
        @type = type
        @options = options
      end

      def to_h
        options.dup
      end

      def validation_subject
        "trigger :#{type}"
      end
    end
  end
end

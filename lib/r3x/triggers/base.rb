module R3x
  module Triggers
    class Base
      attr_reader :type, :options

      def initialize(type, **options)
        @type = type
        @options = options
      end

      def validate!
        raise NotImplementedError, "#{self.class.name} must implement validate!"
      end

      def to_h
        { type: type }.merge(options)
      end
    end
  end
end

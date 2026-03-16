module R3x
  module Triggers
    class Manual < Base
      def initialize(**options)
        super(:manual, **options)
      end

      def validate!
        # Manual trigger requires no options
        true
      end
    end
  end
end

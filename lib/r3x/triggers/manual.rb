module R3x
  module Triggers
    class Manual < Base
      def initialize(**options)
        super(:manual, **options)
      end

      def validate!
        true
      end
    end
  end
end

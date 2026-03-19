module R3x
  module Triggers
    class Manual < Base
      def initialize(**options)
        super(:manual, **options)
      end
    end
  end
end

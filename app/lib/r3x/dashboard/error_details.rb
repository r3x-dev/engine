# frozen_string_literal: true

module R3x
  module Dashboard
    class ErrorDetails
      def initialize(error)
        @details = R3x::ErrorDetails.new(error)
      end

      def summary
        details.summary
      end

      def body
        details.body
      end

      def details_visible?
        details.details_visible?
      end

      def structured
        details.structured
      end

      private

      attr_reader :details
    end
  end
end

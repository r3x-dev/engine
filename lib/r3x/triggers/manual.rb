# frozen_string_literal: true

module R3x
  module Triggers
    class Manual < Base
      def initialize(**)
        super(:manual, **)
      end
    end
  end
end

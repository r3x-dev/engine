# frozen_string_literal: true

module Demo
  module Dashboard
    class BaseJob < ActiveJob::Base
      def perform(*)
      end
    end
  end
end

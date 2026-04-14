module R3x
  module TestSupport
    class DashboardWorkflowJob < ActiveJob::Base
      queue_as :default

      def perform(*)
      end
    end
  end
end

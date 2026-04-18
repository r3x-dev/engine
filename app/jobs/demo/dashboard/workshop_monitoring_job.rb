module Demo
  module Dashboard
    class WorkshopMonitoringJob < BaseJob
      queue_as :default
    end
  end
end

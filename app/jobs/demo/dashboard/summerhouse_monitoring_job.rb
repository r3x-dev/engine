module Demo
  module Dashboard
    class SummerhouseMonitoringJob < BaseJob
      queue_as :default
    end
  end
end

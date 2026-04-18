module Demo
  module Dashboard
    class RetentionCleanupJob < BaseJob
      queue_as :maintenance
    end
  end
end

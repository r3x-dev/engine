# frozen_string_literal: true

module Demo
  module Dashboard
    class MonitoringJob < BaseJob
      queue_as :default
    end
  end
end

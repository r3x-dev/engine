# frozen_string_literal: true

module Workflows
  class StableTriggerWorkflow < R3x::Workflow::Base
    EVENTS = Concurrent::Array.new

    trigger :schedule, key: :daily, cron: "0 8 * * *", timezone: "UTC"

    def run
      step(:prepare) { EVENTS << "prepared" }
      step(:deliver, isolated: true) { EVENTS << "delivered" }
    end
  end
end

# frozen_string_literal: true

module Workflows
  class AdmissionWorkflow < R3x::Workflow::Base
    limits_concurrency to: 1,
      key: ->(_trigger_key = nil, trigger_payload: nil) { trigger_payload&.fetch("partition", nil) || "all" },
      group: ->(*) { "admission/#{self.class.name}" },
      duration: 3.hours

    self.resume_options = { wait: 1.minute }

    trigger :schedule, key: :scheduled, cron: "0 * * * *"
    trigger :manual, key: :manual
    trigger :manual, key: :retry

    retry_on RuntimeError, wait: 1.minute, attempts: 2

    before_enqueue { throw :abort if arguments.first == "abort" }

    def run
      if arguments.first == "manual:retry"
        raise "Try again" if executions == 1

        return
      end

      step :prepare do
        nil
      end

      step :deliver, isolated: true do
        nil
      end
    end
  end
end

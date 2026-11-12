# frozen_string_literal: true

module Workflows
  class RetryWorkflow < R3x::Workflow::Base
    EXECUTIONS = Concurrent::Array.new

    retry_on Timeout::Error, wait: 3.seconds, attempts: 2, jitter: 0

    def self.failures = 1

    def run
      EXECUTIONS << executions
      raise Timeout::Error, "temporary failure" if executions <= self.class.failures

      "recovered"
    end
  end
end

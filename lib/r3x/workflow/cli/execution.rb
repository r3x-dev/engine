# frozen_string_literal: true

module R3x
  module Workflow
    class Cli
      module Execution
        attr_accessor :queue_adapter

        def retry_job(...)
          super || raise(enqueue_error || ActiveJob::EnqueueError.new("Workflow retry enqueue was aborted for #{self.class.name}"))
        end
      end
    end
  end
end

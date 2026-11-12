# frozen_string_literal: true

module R3x
  module Workflow
    class Cli
      class QueueAdapter < ActiveJob::QueueAdapters::AbstractAdapter
        def initialize
          @jobs = []
        end

        def enqueue(job)
          @jobs << job.serialize.deep_dup
        end

        def enqueue_at(job, _timestamp)
          enqueue(job)
        end

        def shift
          @jobs.shift
        end
      end
    end
  end
end

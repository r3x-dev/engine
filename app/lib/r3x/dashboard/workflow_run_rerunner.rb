module R3x
  module Dashboard
    class WorkflowRunRerunner
      TERMINAL_STATUSES = %w[ failed finished ].freeze

      def initialize(run:)
        @run = run
      end

      def enqueue!
        raise ArgumentError, "Workflow run is not rerunnable" unless rerunnable?

        R3x::RunWorkflowJob
          .set(job_options)
          .perform_later(
            run.fetch(:workflow_key),
            trigger_key: run[:trigger_key],
            trigger_payload: run[:trigger_payload]
          )
      end

      private
        attr_reader :run

        def rerunnable?
          run[:known_workflow] && TERMINAL_STATUSES.include?(run[:status].to_s)
        end

        def job_options
          {
            queue: run[:queue_name].presence,
            priority: run[:priority]
          }.compact
        end
    end
  end
end

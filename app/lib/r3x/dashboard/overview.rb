module R3x
  module Dashboard
    class Overview
      ACTIVITY_WINDOW = 24.hours
      RECENT_RUN_LIMIT = 10

      def summary_cards
        counts = run_counts
        running_count = counts.running_count
        recent_activity_count = counts.recent_activity_count(window: ACTIVITY_WINDOW)

        [
          {
            count: needs_attention.count,
            href: "#needs-attention",
            label: "Needs attention",
            note: needs_attention.count == 1 ? "workflow needs a closer look" : "workflows need a closer look"
          },
          {
            count: running_count,
            href: workflow_runs_path(status: "running"),
            label: "Running now",
            note: running_count == 1 ? "run is active right now" : "runs are active right now"
          },
          {
            count: recent_activity_count,
            href: workflow_runs_path,
            label: "Recent activity (24h)",
            note: recent_activity_count == 1 ? "visible run in the last day" : "visible runs in the last day"
          }
        ]
      end

      def needs_attention
        @needs_attention ||= workflows
          .select { |workflow| %w[ failed trigger_error ].include?(workflow.dig(:health, :status)) }
          .map do |workflow|
            workflow.merge(
              attention_at: attention_time_for(workflow),
              attention_label: attention_label_for(workflow)
            )
          end
          .sort_by { |workflow| workflow[:attention_at] || Time.at(0) }
          .reverse
      end

      def recent_runs
        @recent_runs ||= Workflow::Runs.new(
          job_ids: run_counts.recent_run_ids(limit: RECENT_RUN_LIMIT),
          limit: RECENT_RUN_LIMIT
        ).all
      end

      private
        include Rails.application.routes.url_helpers

        def run_counts
          @run_counts ||= Workflow::RunCounts.new
        end

        def workflows
          @workflows ||= Workflow::Summaries.new.all
        end

        def attention_time_for(workflow)
          return workflow.dig(:last_run, :recorded_at) if workflow.dig(:health, :status) == "failed"

          workflow[:trigger_entries]
            .filter_map { |entry| entry[:trigger_state]&.last_error_at }
            .max
        end

        def attention_label_for(workflow)
          return "Failed" if workflow.dig(:health, :status) == "failed"

          "Trigger error"
        end
    end
  end
end

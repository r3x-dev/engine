# frozen_string_literal: true

module R3x
  module Dashboard
    class Overview
      ACTIVITY_WINDOW = 24.hours
      RECENT_RUN_LIMIT = 10

      def summary_cards
        counts = run_counts
        attention_count = needs_attention.size
        running_count = counts.running_count
        recent_activity_count = counts.recent_activity_count(window: ACTIVITY_WINDOW)

        [
          {
            count: attention_count,
            href: "#needs-attention",
            label: "Needs attention",
            note: (attention_count == 1) ? "workflow needs a closer look" : "workflows need a closer look"
          },
          {
            count: running_count,
            href: workflow_runs_path(status: "running"),
            label: "Running now",
            note: (running_count == 1) ? "run is active right now" : "runs are active right now"
          },
          {
            count: recent_activity_count,
            href: workflow_runs_path,
            label: "Recent activity (24h)",
            note: (recent_activity_count == 1) ? "visible run in the last day" : "visible runs in the last day"
          }
        ]
      end

      def needs_attention
        @needs_attention ||= workflows
          .select { |w| w.dig(:health, :status) == "failed" }
          .map { |w| w.merge(attention_at: attention_time_for(w), attention_label: attention_label_for(w)) }
          .sort_by { |w| w[:attention_at] || Time.zone.at(0) }
          .reverse
      end

      def recent_runs
        @recent_runs ||= Workflow::Runs
          .new(job_ids: run_counts.recent_run_ids(limit: RECENT_RUN_LIMIT), limit: RECENT_RUN_LIMIT)
          .all
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
        workflow.dig(:last_run, :recorded_at)
      end

      def attention_label_for(workflow)
        "Failed"
      end
    end
  end
end

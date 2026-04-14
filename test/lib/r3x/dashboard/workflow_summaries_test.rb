require "test_helper"

module R3x
  module Dashboard
    class WorkflowSummariesTest < ActiveSupport::TestCase
      WORKFLOW_JOB_CLASS_NAME = R3x::TestSupport::DashboardWorkflowJob.name.freeze

      setup do
        clear_tables
      end

      test "builds summary with recurring task and healthy status" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:schedule:abc123",
          schedule: "0 * * * *",
          class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          queue_name: "default",
          static: false
        )
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          finished_at: 1.minute.ago,
          created_at: 10.minutes.ago,
          updated_at: 1.minute.ago
        )

        summary = WorkflowSummaries.new.find!("test_workflow")

        assert_equal "Healthy", summary[:health][:label]
        assert summary[:next_trigger_at].present?
        assert_equal 1, summary[:trigger_entries].size
        assert summary[:trigger_entries].first[:recurring_task].present?
        assert summary[:trigger_entries].first[:run_now_available]
      end

      test "prefers trigger error health over last run status" do
        R3x::TriggerState.create!(
          workflow_key: "test_dashboard_change_feed",
          trigger_key: "feed:123",
          trigger_type: "fake_change_detecting",
          state: {},
          last_error_at: Time.current,
          last_error_message: "feed offline"
        )

        summary = WorkflowSummaries.new.find!("test_dashboard_change_feed")

        assert_equal "Trigger error", summary[:health][:label]
        assert_equal "feed offline", summary[:health][:detail]
      end

      private
        def clear_tables
          TestDbCleanup.clear_runtime_tables!
        end
    end
  end
end

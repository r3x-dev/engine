require "test_helper"

module R3x
  module Dashboard
    class WorkflowCatalogTest < ActiveSupport::TestCase
      WORKFLOW_JOB_CLASS_NAME = R3x::TestSupport::DashboardWorkflowJob.name.freeze

      setup do
        TestDbCleanup.clear_runtime_tables!
      end

      teardown do
        TestDbCleanup.clear_runtime_tables!
      end

      test "collects workflow keys from recurring tasks trigger states and legacy runs" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:scheduled_workflow:schedule:123",
          schedule: "0 * * * *",
          class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:123" ],
          queue_name: "default",
          static: false
        )
        R3x::TriggerState.create!(
          workflow_key: "observed_workflow",
          trigger_key: "feed:1",
          trigger_type: "feed",
          state: {}
        )
        DashboardJobRows.create_job!(
          job_class_name: "R3x::RunWorkflowJob",
          arguments: [ "legacy_workflow", { "trigger_key" => "manual:legacy" } ],
          finished_at: 1.minute.ago,
          created_at: 2.minutes.ago,
          updated_at: 1.minute.ago
        )

        assert_equal [ "legacy_workflow", "observed_workflow", "scheduled_workflow" ], WorkflowCatalog.new.workflow_keys
      end

      test "maps concrete workflow class names to workflow keys and excludes change detection jobs" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:schedule:123",
          schedule: "0 * * * *",
          class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:123" ],
          queue_name: "default",
          static: false
        )
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:feed:123",
          schedule: "*/5 * * * *",
          class_name: WorkflowCatalog::CHANGE_DETECTION_CLASS_NAME,
          arguments: [ "test_workflow", { "trigger_key" => "feed:123" } ],
          queue_name: "feeds",
          static: false
        )

        catalog = WorkflowCatalog.new

        assert_equal [ WORKFLOW_JOB_CLASS_NAME ], catalog.class_names_for("test_workflow")
        assert_equal({ WORKFLOW_JOB_CLASS_NAME => "test_workflow" }, catalog.class_names_to_keys)
      end

      test "find raises for unknown workflow" do
        error = assert_raises(KeyError) do
          WorkflowCatalog.new.find!("missing_workflow")
        end

        assert_equal "Unknown workflow 'missing_workflow'", error.message
      end
    end
  end
end

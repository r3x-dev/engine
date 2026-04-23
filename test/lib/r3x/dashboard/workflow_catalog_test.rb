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

      test "collects workflow keys from recurring tasks trigger states and observed direct runs" do
        observed_job_class_name = ensure_dashboard_job_class("ObservedWorkflowJob").name

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
          job_class_name: observed_job_class_name,
          arguments: [ "feed:1" ],
          finished_at: 1.minute.ago,
          created_at: 2.minutes.ago,
          updated_at: 1.minute.ago
        )

        assert_equal [ "observed_workflow", "scheduled_workflow" ], Workflow::Catalog.new.workflow_keys
      end

      test "derives workflow keys from observed direct workflow class names without trigger metadata" do
        DashboardJobRows.create_job!(
          job_class_name: "Workflows::ManualOnlyWorkflow",
          arguments: [],
          finished_at: 1.minute.ago,
          created_at: 2.minutes.ago,
          updated_at: 1.minute.ago
        )

        catalog = Workflow::Catalog.new

        assert_equal [ "Workflows::ManualOnlyWorkflow" ], catalog.class_names_for("manual_only_workflow")
        assert_equal [ "manual_only_workflow" ], catalog.workflow_keys
      end

      test "keeps manual-only direct workflows discoverable with more than 250 newer jobs" do
        DashboardJobRows.create_job!(
          job_class_name: "Workflows::ManualOnlyWorkflow",
          arguments: [],
          finished_at: 20.minutes.ago,
          created_at: 20.minutes.ago,
          updated_at: 20.minutes.ago
        )

        300.times do |index|
          DashboardJobRows.create_job!(
            job_class_name: "CleanupJob",
            arguments: [ "tmp/#{index}" ],
            finished_at: 1.minute.ago,
            created_at: 1.minute.ago + index.seconds,
            updated_at: 1.minute.ago + index.seconds
          )
        end

        catalog = Workflow::Catalog.new

        assert_includes catalog.workflow_keys, "manual_only_workflow"
        assert_includes catalog.class_names_for("manual_only_workflow"), "Workflows::ManualOnlyWorkflow"
      end

      test "maps concrete workflow class names to workflow keys and excludes unrelated and change detection jobs" do
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
          class_name: Workflow::Catalog::CHANGE_DETECTION_CLASS_NAME,
          arguments: [ "test_workflow", { "trigger_key" => "feed:123" } ],
          queue_name: "feeds",
          static: false
        )
        DashboardJobRows.create_job!(
          job_class_name: "CleanupJob",
          arguments: [ "tmp/cache" ],
          finished_at: 1.minute.ago,
          created_at: 2.minutes.ago,
          updated_at: 1.minute.ago
        )

        catalog = Workflow::Catalog.new

        assert_equal [ WORKFLOW_JOB_CLASS_NAME ], catalog.class_names_for("test_workflow")
        assert_equal({ WORKFLOW_JOB_CLASS_NAME => "test_workflow" }, catalog.class_names_to_keys)
      end

      test "find raises for unknown workflow" do
        error = assert_raises(KeyError) do
          Workflow::Catalog.new.find!("missing_workflow")
        end

        assert_equal "Unknown workflow 'missing_workflow'", error.message
      end

      private
        def ensure_dashboard_job_class(name)
          test_jobs = if Object.const_defined?(:TestDashboardJobs, false)
            Object.const_get(:TestDashboardJobs)
          else
            Object.const_set(:TestDashboardJobs, Module.new)
          end

          return test_jobs.const_get(name, false) if test_jobs.const_defined?(name, false)

          test_jobs.const_set(name, Class.new(R3x::TestSupport::DashboardWorkflowJob))
        end
    end
  end
end

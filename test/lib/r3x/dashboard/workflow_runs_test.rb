require "test_helper"

module R3x
  module Dashboard
    class WorkflowRunsTest < ActiveSupport::TestCase
      WORKFLOW_JOB_CLASS_NAME = R3x::TestSupport::DashboardWorkflowJob.name.freeze

      setup do
        TestDbCleanup.clear_runtime_tables!
        seed_runtime_catalog
      end

      teardown do
        TestDbCleanup.clear_runtime_tables!
      end

      test "maps workflow jobs to workflow_key and finished status" do
        job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          finished_at: 2.minutes.ago,
          created_at: 5.minutes.ago,
          updated_at: 2.minutes.ago
        )

        run = Workflow::Runs.new.all.find { |entry| entry[:job_id] == job.id }

        assert_equal "test_workflow", run[:workflow_key]
        assert_equal "finished", run[:status]
        assert_equal "schedule:abc123", run[:trigger_key]
      end

      test "maps trigger payload for workflow jobs" do
        payload = { "changed_ids" => [ "a1" ] }
        job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123", { trigger_payload: payload } ],
          finished_at: 2.minutes.ago,
          created_at: 5.minutes.ago,
          updated_at: 2.minutes.ago
        )

        run = Workflow::Runs.new.all.find { |entry| entry[:job_id] == job.id }

        assert_equal payload, run[:trigger_payload]
      end

      test "maps failed jobs from failed execution table" do
        job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          created_at: 5.minutes.ago,
          updated_at: 1.minute.ago
        )
        SolidQueue::FailedExecution.create!(job_id: job.id, error: "boom", created_at: 1.minute.ago)

        run = Workflow::Runs.new.all.find { |entry| entry[:job_id] == job.id }

        assert_equal "failed", run[:status]
        assert_equal "boom", run[:error]
      end

      test "maps change-detection-driven workflow runs through trigger state observations" do
        observed_job_class_name = ensure_dashboard_job_class("FeedWorkflowJob").name

        R3x::TriggerState.create!(
          workflow_key: "feed_workflow",
          trigger_key: "feed:123",
          trigger_type: "feed",
          state: {}
        )
        job = DashboardJobRows.create_job!(
          job_class_name: observed_job_class_name,
          arguments: [ "feed:123", { trigger_payload: { "id" => "99" } } ],
          finished_at: 1.minute.ago,
          created_at: 5.minutes.ago,
          updated_at: 1.minute.ago
        )

        run = Workflow::Runs.new(workflow_key: "feed_workflow").all.find { |entry| entry[:job_id] == job.id }

        assert_equal "feed_workflow", run[:workflow_key]
        assert_equal "feed:123", run[:trigger_key]
      end

      test "maps manual-only workflow runs from direct workflow class names without trigger metadata" do
        job = DashboardJobRows.create_job!(
          job_class_name: "Workflows::ManualOnlyWorkflow",
          arguments: [],
          finished_at: 1.minute.ago,
          created_at: 5.minutes.ago,
          updated_at: 1.minute.ago
        )

        run = Workflow::Runs.new(workflow_key: "manual_only_workflow").all.find { |entry| entry[:job_id] == job.id }

        assert_equal "manual_only_workflow", run[:workflow_key]
        assert_nil run[:trigger_key]
      end

      test "ignores unrelated non-workflow rows entirely" do
        job = DashboardJobRows.create_job!(
          job_class_name: "CleanupJob",
          arguments: [ "tmp/cache" ],
          finished_at: 1.minute.ago,
          created_at: 5.minutes.ago,
          updated_at: 1.minute.ago
        )

        runs = Workflow::Runs.new.all

        refute_includes runs.map { |entry| entry[:job_id] }, job.id
      end

      test "filters by workflow and status" do
        finished_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          finished_at: 2.minutes.ago,
          created_at: 10.minutes.ago,
          updated_at: 2.minutes.ago
        )
        failed_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          created_at: 5.minutes.ago,
          updated_at: 1.minute.ago
        )
        SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "bad", created_at: 1.minute.ago)

        runs = Workflow::Runs.new(workflow_key: "test_workflow", status: "failed").all

        assert_equal [ failed_job.id ], runs.map { |run| run[:job_id] }
        refute_includes runs.map { |run| run[:job_id] }, finished_job.id
      end

      test "ignores unrelated active jobs" do
        DashboardJobRows.create_job!(
          job_class_name: "CleanupJob",
          arguments: [ "tmp/cache" ],
          finished_at: 1.minute.ago,
          created_at: 2.minutes.ago,
          updated_at: 1.minute.ago
        )

        runs = Workflow::Runs.new.all

        assert_empty runs
      end

      test "workflow and status filters are not crowded out by newer unrelated jobs" do
        failed_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          created_at: 10.minutes.ago,
          updated_at: 9.minutes.ago
        )
        SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "bad", created_at: 9.minutes.ago)

        75.times do |index|
          DashboardJobRows.create_job!(
            job_class_name: "CleanupJob",
            arguments: [ "tmp/#{index}" ],
            finished_at: 1.minute.ago,
            created_at: 1.minute.ago + index.seconds,
            updated_at: 1.minute.ago + index.seconds
          )
        end

        runs = Workflow::Runs.new(workflow_key: "test_workflow", status: "failed", limit: 10).all

        assert_equal [ failed_job.id ], runs.map { |run| run[:job_id] }
      end

      test "ignores change detection jobs in workflow run history" do
        DashboardJobRows.create_job!(
          job_class_name: "R3x::ChangeDetectionJob",
          arguments: [ "test_workflow", { "trigger_key" => "feed:123" } ],
          created_at: 5.minutes.ago,
          updated_at: 1.minute.ago
        )

        runs = Workflow::Runs.new.all

        assert_empty runs
      end

      private
        def seed_runtime_catalog
          SolidQueue::RecurringTask.create!(
            key: "workflow:test_workflow:schedule:abc123",
            schedule: "0 * * * *",
            class_name: WORKFLOW_JOB_CLASS_NAME,
            arguments: [ "schedule:abc123" ],
            queue_name: "default",
            static: false
          )
        end

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

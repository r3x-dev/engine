require "test_helper"

module R3x
  module Dashboard
    class WorkflowRunEnqueuerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        TestDbCleanup.clear_runtime_tables!
        clear_enqueued_jobs
      end

      teardown do
        clear_enqueued_jobs
        TestDbCleanup.clear_runtime_tables!
      end

      test "enqueue without trigger key queues generic run workflow job" do
        assert_enqueued_with(job: R3x::RunWorkflowJob, args: [ "test_workflow", { trigger_key: nil } ]) do
          WorkflowRunEnqueuer.new(workflow_key: "test_workflow", trigger_key: nil).enqueue!
        end
      end

      test "enqueue with recurring workflow trigger uses recurring task queue and priority" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:schedule:123",
          schedule: "0 * * * *",
          class_name: R3x::TestSupport::DashboardWorkflowJob.name,
          arguments: [ "schedule:123" ],
          queue_name: "critical",
          priority: 7,
          static: false
        )

        assert_enqueued_with(
          job: R3x::RunWorkflowJob,
          args: [ "test_workflow", { trigger_key: "schedule:123" } ],
          queue: "critical",
          priority: 7
        ) do
          WorkflowRunEnqueuer.new(workflow_key: "test_workflow", trigger_key: "schedule:123").enqueue!
        end
      end

      test "enqueue with change-detection task uses change detection job" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:feed:123",
          schedule: "*/5 * * * *",
          class_name: "R3x::ChangeDetectionJob",
          arguments: [ "test_workflow", { "trigger_key" => "feed:123" } ],
          queue_name: "feeds",
          priority: 3,
          static: false
        )

        assert_enqueued_with(
          job: R3x::ChangeDetectionJob,
          args: [ "test_workflow", { trigger_key: "feed:123" } ],
          queue: "feeds",
          priority: 3
        ) do
          WorkflowRunEnqueuer.new(workflow_key: "test_workflow", trigger_key: "feed:123").enqueue!
        end
      end

      test "enqueue with unknown trigger key raises from recurring task lookup" do
        assert_raises(ActiveRecord::RecordNotFound) do
          WorkflowRunEnqueuer.new(workflow_key: "test_workflow", trigger_key: "missing:123").enqueue!
        end
      end
    end
  end
end

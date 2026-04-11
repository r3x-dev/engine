require "test_helper"

module R3x
  module Dashboard
    class WorkflowRunsTest < ActiveSupport::TestCase
      setup do
        @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
        ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
        Workflow::PackLoader.load!(force: true)
        clear_queue_tables
      end

      teardown do
        clear_queue_tables
        ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
        Workflow::Registry.reset!
      end

      test "maps workflow jobs to workflow_key and finished status" do
        workflow_class = Workflow::Registry.fetch("test_workflow")
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: workflow_class.name,
          arguments: [ workflow_class.triggers.first.unique_key ],
          finished_at: 2.minutes.ago,
          created_at: 5.minutes.ago,
          updated_at: 2.minutes.ago
        )

        runs = WorkflowRuns.new.all
        run = runs.find { |entry| entry[:job_id] == job.id }

        assert_equal "test_workflow", run[:workflow_key]
        assert_equal "finished", run[:status]
        assert_equal workflow_class.triggers.first.unique_key, run[:trigger_key]
      end

      test "maps failed jobs from failed execution table" do
        workflow_class = Workflow::Registry.fetch("test_workflow")
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: workflow_class.name,
          arguments: [ workflow_class.triggers.first.unique_key ],
          created_at: 5.minutes.ago,
          updated_at: 1.minute.ago
        )
        SolidQueue::FailedExecution.create!(job_id: job.id, error: "boom", created_at: 1.minute.ago)

        run = WorkflowRuns.new.all.find { |entry| entry[:job_id] == job.id }

        assert_equal "failed", run[:status]
        assert_equal "boom", run[:error]
      end

      test "supports legacy run_workflow_job rows" do
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "R3x::RunWorkflowJob",
          arguments: [ "test_workflow", { "trigger_key" => "manual:legacy" } ],
          finished_at: 1.minute.ago,
          created_at: 5.minutes.ago,
          updated_at: 1.minute.ago
        )

        run = WorkflowRuns.new.all.find { |entry| entry[:job_id] == job.id }

        assert_equal "test_workflow", run[:workflow_key]
        assert_equal "manual:legacy", run[:trigger_key]
      end

      test "filters by workflow and status" do
        workflow_class = Workflow::Registry.fetch("test_workflow")
        finished_job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: workflow_class.name,
          arguments: [ workflow_class.triggers.first.unique_key ],
          finished_at: 2.minutes.ago,
          created_at: 10.minutes.ago,
          updated_at: 2.minutes.ago
        )
        failed_job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: workflow_class.name,
          arguments: [ workflow_class.triggers.first.unique_key ],
          created_at: 5.minutes.ago,
          updated_at: 1.minute.ago
        )
        SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "bad", created_at: 1.minute.ago)

        runs = WorkflowRuns.new(workflow_key: "test_workflow", status: "failed").all

        assert_equal [ failed_job.id ], runs.map { |run| run[:job_id] }
        refute_includes runs.map { |run| run[:job_id] }, finished_job.id
      end

      private
        def clear_queue_tables
          SolidQueue::BlockedExecution.delete_all
          SolidQueue::ClaimedExecution.delete_all
          SolidQueue::FailedExecution.delete_all
          SolidQueue::ReadyExecution.delete_all
          SolidQueue::ScheduledExecution.delete_all
          SolidQueue::Job.delete_all
        end
    end
  end
end

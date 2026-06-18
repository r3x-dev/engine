require "test_helper"

module R3x
  module Dashboard
    class WorkflowRunsTest < ActiveSupport::TestCase
      WORKFLOW_JOB_CLASS_NAME = DashboardTestWorkflows.ensure_class("TestWorkflow").freeze

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
        assert_equal "0 * * * *", run[:trigger_schedule]
        assert_equal job.created_at, run[:started_at]
      end

      test "groups resumed workflow fragments into one logical run" do
        active_job_id = "aj-resumed-workflow"
        initial_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          active_job_id: active_job_id,
          finished_at: 3.minutes.ago,
          created_at: 5.minutes.ago,
          updated_at: 3.minutes.ago
        )
        resumed_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          active_job_id: active_job_id,
          created_at: 3.minutes.ago,
          updated_at: 3.minutes.ago,
          scheduled_at: 2.minutes.from_now
        )
        resumed_job.update!(arguments: resumed_job.arguments.merge("resumptions" => 1))
        SolidQueue::ReadyExecution.where(job_id: resumed_job.id).delete_all
        scheduled_execution = SolidQueue::ScheduledExecution.find_or_initialize_by(job_id: resumed_job.id)
        scheduled_execution.update!(
          queue_name: resumed_job.queue_name,
          priority: resumed_job.priority,
          scheduled_at: resumed_job.scheduled_at,
          created_at: resumed_job.created_at
        )

        runs = Workflow::Runs.new.all.select { |entry| entry[:active_job_id] == active_job_id }

        assert_equal 1, runs.size
        assert_equal resumed_job.id, runs.first[:job_id]
        assert_equal "sleeping", runs.first[:status]
        assert_equal 1, runs.first[:resumptions]
        assert_equal initial_job.created_at.to_i, runs.first[:enqueued_at].to_i
        assert_nil runs.first[:finished_at]
      end

      test "counts the final resumed execution in a finished logical run" do
        active_job_id = "aj-finished-after-two-resumes"
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          active_job_id: active_job_id,
          finished_at: 5.minutes.ago,
          created_at: 7.minutes.ago,
          updated_at: 5.minutes.ago
        )
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          active_job_id: active_job_id,
          finished_at: 3.minutes.ago,
          created_at: 5.minutes.ago,
          updated_at: 3.minutes.ago
        )
        final_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          active_job_id: active_job_id,
          finished_at: 1.minute.ago,
          created_at: 3.minutes.ago,
          updated_at: 1.minute.ago
        )
        final_job.update!(
          arguments: final_job.arguments.merge(
            "continuation" => { "completed" => [ "check_camera_1", "check_camera_2" ] },
            "resumptions"  => 1
          )
        )

        runs = Workflow::Runs.new.all.select { |entry| entry[:active_job_id] == active_job_id }

        assert_equal 1, runs.size
        assert_equal final_job.id, runs.first[:job_id]
        assert_equal "finished", runs.first[:status]
        assert_equal 2, runs.first[:resumptions]
      end

      test "sleeping filter includes scheduled resumed workflow fragments" do
        active_job_id = "aj-scheduled-resume"
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          active_job_id: active_job_id,
          finished_at: 3.minutes.ago,
          created_at: 5.minutes.ago,
          updated_at: 3.minutes.ago
        )
        resumed_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          active_job_id: active_job_id,
          created_at: 3.minutes.ago,
          updated_at: 3.minutes.ago,
          scheduled_at: 2.minutes.from_now
        )
        resumed_job.update!(arguments: resumed_job.arguments.merge("resumptions" => 1))
        SolidQueue::ReadyExecution.where(job_id: resumed_job.id).delete_all
        scheduled_execution = SolidQueue::ScheduledExecution.find_or_initialize_by(job_id: resumed_job.id)
        scheduled_execution.update!(
          queue_name: resumed_job.queue_name,
          priority: resumed_job.priority,
          scheduled_at: resumed_job.scheduled_at,
          created_at: resumed_job.created_at
        )

        runs = Workflow::Runs.new(status: "sleeping").all

        assert_includes runs.map { |run| run[:active_job_id] }, active_job_id
      end

      test "sleeping filter is not crowded out by newer queued workflow jobs" do
        active_job_id = "aj-old-sleeping-run"
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          active_job_id: active_job_id,
          finished_at: 2.hours.ago,
          created_at: 3.hours.ago,
          updated_at: 2.hours.ago
        )
        sleeping_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          active_job_id: active_job_id,
          created_at: 2.hours.ago,
          updated_at: 2.hours.ago,
          scheduled_at: 1.hour.from_now
        )
        sleeping_job.update!(arguments: sleeping_job.arguments.merge("resumptions" => 1))
        SolidQueue::ReadyExecution.where(job_id: sleeping_job.id).delete_all
        SolidQueue::ScheduledExecution.find_or_initialize_by(job_id: sleeping_job.id).update!(
          queue_name: sleeping_job.queue_name,
          priority: sleeping_job.priority,
          scheduled_at: sleeping_job.scheduled_at,
          created_at: sleeping_job.created_at
        )

        75.times do |index|
          DashboardJobRows.create_job!(
            job_class_name: WORKFLOW_JOB_CLASS_NAME,
            arguments: [ "schedule:abc123" ],
            created_at: index.seconds.ago,
            updated_at: index.seconds.ago
          )
        end

        runs = Workflow::Runs.new(status: "sleeping", limit: 10).all

        assert_includes runs.map { |run| run[:active_job_id] }, active_job_id
        assert_equal "sleeping", runs.find { |run| run[:active_job_id] == active_job_id }[:status]
      end

      test "started_at uses claimed_execution time for running jobs" do
        job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          created_at: 5.minutes.ago,
          updated_at: 2.minutes.ago
        )
        process = SolidQueue::Process.create!(
          name: "test-worker-1",
          kind: "Worker",
          pid: $$,
          hostname: "localhost",
          last_heartbeat_at: Time.current,
          created_at: Time.current
        )
        claimed_at = 2.minutes.ago
        SolidQueue::ClaimedExecution.create!(job_id: job.id, process_id: process.id, created_at: claimed_at)

        run = Workflow::Runs.new.all.find { |entry| entry[:job_id] == job.id }

        assert_equal "running", run[:status]
        assert_equal claimed_at.to_i, run[:started_at].to_i
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
    end
  end
end

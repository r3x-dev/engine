require "test_helper"

module R3x
  module Dashboard
    class WorkflowRunCountsTest < ActiveSupport::TestCase
      WORKFLOW_JOB_CLASS_NAME = R3x::TestSupport::DashboardWorkflowJob.name.freeze

      setup do
        TestDbCleanup.clear_runtime_tables!
        seed_runtime_catalog
      end

      teardown do
        TestDbCleanup.clear_runtime_tables!
      end

      test "counts running jobs and recent activity with dashboard visibility semantics" do
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          finished_at: 2.hours.ago,
          created_at: 3.hours.ago,
          updated_at: 2.hours.ago
        )

        failed_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          created_at: 4.hours.ago,
          updated_at: 3.hours.ago
        )
        SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "boom", created_at: 3.hours.ago)

        running_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          created_at: 6.hours.ago,
          updated_at: 5.hours.ago
        )
        claim_job!(running_job, claimed_at: 20.minutes.ago)

        queued_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          created_at: 12.hours.ago,
          updated_at: 12.hours.ago
        )
        SolidQueue::ReadyExecution.find_by!(job_id: queued_job.id).update!(created_at: 15.minutes.ago)

        scheduled_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          created_at: 2.days.ago,
          updated_at: 2.days.ago,
          scheduled_at: 45.minutes.ago
        )
        SolidQueue::ScheduledExecution.create!(
          job_id: scheduled_job.id,
          queue_name: scheduled_job.queue_name,
          priority: scheduled_job.priority,
          scheduled_at: 45.minutes.ago,
          created_at: 2.days.ago
        )

        DashboardJobRows.create_job!(
          job_class_name: "CleanupJob",
          arguments: [ "tmp/cache" ],
          finished_at: 30.minutes.ago,
          created_at: 45.minutes.ago,
          updated_at: 30.minutes.ago
        )

        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          finished_at: 2.days.ago,
          created_at: 2.days.ago - 5.minutes,
          updated_at: 2.days.ago
        )

        DashboardJobRows.create_job!(
          job_class_name: "R3x::ChangeDetectionJob",
          arguments: [ "test_workflow", { trigger_key: "feed:123" } ],
          created_at: 10.minutes.ago,
          updated_at: 10.minutes.ago
        )

        counts = Workflow::RunCounts.new

        assert_equal 1, counts.running_count
        assert_equal 5, counts.recent_activity_count(window: 24.hours)
      end

      test "does not count future scheduled runs as recent activity" do
        scheduled_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          created_at: Time.current,
          updated_at: Time.current,
          scheduled_at: 2.hours.from_now
        )
        SolidQueue::ScheduledExecution.find_by!(job_id: scheduled_job.id).update!(
          scheduled_at: 2.hours.from_now,
          created_at: Time.current
        )

        counts = Workflow::RunCounts.new

        assert_equal 0, counts.recent_activity_count(window: 24.hours)
      end

      test "recent run ids include long-running jobs that completed most recently" do
        long_running_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          finished_at: 5.seconds.ago,
          created_at: 2.days.ago,
          updated_at: 5.seconds.ago
        )

        12.times do |index|
          finished_at = (20 - index).minutes.ago

          DashboardJobRows.create_job!(
            job_class_name: WORKFLOW_JOB_CLASS_NAME,
            arguments: [ "schedule:abc123" ],
            finished_at: finished_at,
            created_at: finished_at - 30.seconds,
            updated_at: finished_at
          )
        end

        runs = Workflow::Runs.new(job_ids: Workflow::RunCounts.new.recent_run_ids(limit: 10), limit: 10).all

        assert_equal long_running_job.id, runs.first[:job_id]
      end

      test "recent run ids ignore unrelated non-workflow rows entirely" do
        60.times do |index|
          finished_at = (index + 1).minutes.ago

          DashboardJobRows.create_job!(
            job_class_name: "CleanupJob",
            arguments: [ "tmp/#{index}" ],
            finished_at: finished_at,
            created_at: finished_at - 30.seconds,
            updated_at: finished_at
          )
        end

        10.times do |index|
          finished_at = (90 + index).minutes.ago

          DashboardJobRows.create_job!(
            job_class_name: WORKFLOW_JOB_CLASS_NAME,
            arguments: [ "schedule:abc123" ],
            finished_at: finished_at,
            created_at: finished_at - 30.seconds,
            updated_at: finished_at
          )
        end

        runs = Workflow::Runs.new(job_ids: Workflow::RunCounts.new.recent_run_ids(limit: 10), limit: 10).all

        assert_equal 10, runs.size
        assert runs.all? { |run| run[:class_name] == WORKFLOW_JOB_CLASS_NAME }
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

        def claim_job!(job, claimed_at:)
          process = SolidQueue::Process.create!(
            kind: "Worker",
            last_heartbeat_at: Time.current,
            pid: Process.pid,
            hostname: "test",
            metadata: "{}",
            name: "test-worker-#{job.id}",
            created_at: Time.current
          )

          SolidQueue::ClaimedExecution.create!(job_id: job.id, process_id: process.id, created_at: claimed_at)
        end
    end
  end
end

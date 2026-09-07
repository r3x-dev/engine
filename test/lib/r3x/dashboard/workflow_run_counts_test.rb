# frozen_string_literal: true

require "test_helper"

module R3x
  module Dashboard
    class WorkflowRunCountsTest < ActiveSupport::TestCase
      WORKFLOW_JOB_CLASS_NAME = DashboardTestWorkflows.ensure_class("TestWorkflow").freeze

      setup do
        TestDbCleanup.clear_runtime_tables!
        seed_runtime_catalog
      end

      teardown do
        TestDbCleanup.clear_runtime_tables!
      end

      test "counts distinct activity without instantiating job rows" do
        ["resumed-run", "resumed-run", nil, nil, "", "", " ", " "].each do |active_job_id|
          DashboardJobRows.create_job!(
            job_class_name: WORKFLOW_JOB_CLASS_NAME,
            arguments: [],
            active_job_id:,
            created_at: 2.hours.ago,
            finished_at: 1.hour.ago,
          )
        end
        failed = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME, arguments: [], active_job_id: "resumed-run", created_at: 30.minutes.ago,
        )
        SolidQueue::FailedExecution.create!(job_id: failed.id, error: "failure", created_at: 20.minutes.ago)
        instantiated_rows = []
        subscriber = ->(event) do
          instantiated_rows << event.payload[:record_count] if event.payload[:class_name] == "Dashboard::Run"
        end

        ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
          assert_equal 7, Workflow::RunCounts.new.recent_activity_count(window: 24.hours)
        end

        assert_empty instantiated_rows
      end

      test "recent activity skips run queries when the catalog has no workflow classes" do
        counts = Workflow::RunCounts.new
        counts.stubs(:direct_class_names).returns([])
        ::Dashboard::Run.expects(:dashboard_visible).never

        assert_equal 0, counts.recent_activity_count(window: 24.hours)
      end

      test "activity window includes its boundaries and excludes older and future activity" do
        travel_to(Time.current.change(usec: 0)) do
          [24.hours.ago - 1.second, 24.hours.ago, Time.current, 1.second.from_now].each do |finished_at|
            DashboardJobRows.create_job!(
              job_class_name: WORKFLOW_JOB_CLASS_NAME, arguments: [], created_at: 3.days.ago, finished_at:,
            )
          end

          assert_equal 2, Workflow::RunCounts.new.recent_activity_count(window: 24.hours)
        end
      end

      test "counts running jobs and recent activity with dashboard visibility semantics" do
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          finished_at: 2.hours.ago,
          created_at: 3.hours.ago,
          updated_at: 2.hours.ago,
        )

        failed_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          created_at: 4.hours.ago,
          updated_at: 3.hours.ago,
        )
        SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "boom", created_at: 3.hours.ago)

        running_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          created_at: 6.hours.ago,
          updated_at: 5.hours.ago,
        )
        claim_job!(running_job, claimed_at: 20.minutes.ago)

        queued_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          created_at: 12.hours.ago,
          updated_at: 12.hours.ago,
        )
        SolidQueue::ReadyExecution.find_by!(job_id: queued_job.id).update!(created_at: 15.minutes.ago)

        scheduled_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          created_at: 2.days.ago,
          updated_at: 2.days.ago,
          scheduled_at: 45.minutes.ago,
        )
        SolidQueue::ScheduledExecution.create!(
          job_id: scheduled_job.id,
          queue_name: scheduled_job.queue_name,
          priority: scheduled_job.priority,
          scheduled_at: 45.minutes.ago,
          created_at: 2.days.ago,
        )

        DashboardJobRows.create_job!(
          job_class_name: "CleanupJob",
          arguments: ["tmp/cache"],
          finished_at: 30.minutes.ago,
          created_at: 45.minutes.ago,
          updated_at: 30.minutes.ago,
        )

        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          finished_at: 2.days.ago,
          created_at: 2.days.ago - 5.minutes,
          updated_at: 2.days.ago,
        )

        counts = Workflow::RunCounts.new

        assert_equal 1, counts.running_count
        assert_equal 5, counts.recent_activity_count(window: 24.hours)
      end

      test "does not count future scheduled runs as recent activity" do
        scheduled_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          created_at: Time.current,
          updated_at: Time.current,
          scheduled_at: 2.hours.from_now,
        )
        SolidQueue::ScheduledExecution.find_by!(job_id: scheduled_job.id).update!(
          scheduled_at: 2.hours.from_now,
          created_at: Time.current,
        )

        counts = Workflow::RunCounts.new

        assert_equal 0, counts.recent_activity_count(window: 24.hours)
      end

      test "does not count scheduled resumed fragments as running" do
        active_job_id = "aj-counted-resume"
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          active_job_id:,
          finished_at: 3.minutes.ago,
          created_at: 5.minutes.ago,
          updated_at: 3.minutes.ago,
        )
        resumed_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          active_job_id:,
          created_at: 3.minutes.ago,
          updated_at: 3.minutes.ago,
          scheduled_at: 2.minutes.from_now,
        )
        resumed_job.update!(arguments: resumed_job.arguments.merge("resumptions" => 1))
        SolidQueue::ReadyExecution.where(job_id: resumed_job.id).delete_all
        scheduled_execution = SolidQueue::ScheduledExecution.find_or_initialize_by(job_id: resumed_job.id)
        scheduled_execution.update!(
          queue_name: resumed_job.queue_name,
          priority: resumed_job.priority,
          scheduled_at: resumed_job.scheduled_at,
          created_at: resumed_job.created_at,
        )

        assert_equal 0, Workflow::RunCounts.new.running_count
      end

      test "running count ignores queued backlog" do
        running_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          created_at: 2.hours.ago,
          updated_at: 2.hours.ago,
        )
        claim_job!(running_job, claimed_at: 2.hours.ago)

        active_job_id = "aj-counted-sleeping"
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          active_job_id:,
          finished_at: 2.hours.ago,
          created_at: 3.hours.ago,
          updated_at: 2.hours.ago,
        )
        sleeping_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          active_job_id:,
          created_at: 2.hours.ago,
          updated_at: 2.hours.ago,
          scheduled_at: 1.hour.from_now,
        )
        sleeping_job.update!(arguments: sleeping_job.arguments.merge("resumptions" => 1))
        SolidQueue::ReadyExecution.where(job_id: sleeping_job.id).delete_all
        SolidQueue::ScheduledExecution.find_or_initialize_by(job_id: sleeping_job.id).update!(
          queue_name: sleeping_job.queue_name,
          priority: sleeping_job.priority,
          scheduled_at: sleeping_job.scheduled_at,
          created_at: sleeping_job.created_at,
        )

        75.times do |index|
          DashboardJobRows.create_job!(
            job_class_name: WORKFLOW_JOB_CLASS_NAME,
            arguments: ["schedule:abc123"],
            created_at: index.seconds.ago,
            updated_at: index.seconds.ago,
          )
        end

        assert_equal 1, Workflow::RunCounts.new.running_count
      end

      private

      def seed_runtime_catalog
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:schedule:abc123",
          schedule: "0 * * * *",
          class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          queue_name: "default",
          static: false,
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
          created_at: Time.current,
        )

        SolidQueue::ClaimedExecution.create!(job_id: job.id, process_id: process.id, created_at: claimed_at)
      end
    end
  end
end

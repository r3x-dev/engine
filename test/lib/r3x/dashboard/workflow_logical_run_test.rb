# frozen_string_literal: true

require "test_helper"

module R3x
  module Dashboard
    class WorkflowLogicalRunTest < ActiveSupport::TestCase
      WORKFLOW_JOB_CLASS_NAME = DashboardTestWorkflows.ensure_class("TestWorkflow").freeze

      setup do
        TestDbCleanup.clear_runtime_tables!
      end

      teardown do
        TestDbCleanup.clear_runtime_tables!
      end

      test "builds the full logical run hash for resumed workflow fragments" do
        active_job_id = "aj-logical-run"
        initial_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123", { trigger_payload: { "id" => "42" } }],
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
        recurring_task = SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:schedule:abc123",
          schedule: "0 * * * *",
          class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          queue_name: "default",
          static: false,
        )

        runs = ::Dashboard::Run.with_execution_associations.where(id: [initial_job.id, resumed_job.id]).to_a
        logical_run = Workflow::LogicalRun.new(
          jobs: runs,
          workflow_key: "test_workflow",
          recurring_task:,
        ).to_h

        assert_equal active_job_id, logical_run[:active_job_id]
        assert_equal resumed_job.id, logical_run[:job_id]
        assert_equal "sleeping", logical_run[:status]
        assert_equal 1, logical_run[:resumptions]
        assert_nil logical_run[:finished_at]
        assert_equal "schedule:abc123", logical_run[:trigger_key]
        assert_equal({ "id" => "42" }, logical_run[:trigger_payload])
        assert_equal "0 * * * *", logical_run[:trigger_schedule]
        assert_equal initial_job.created_at.to_i, logical_run[:enqueued_at].to_i
      end

      test "builds the summary hash for workflow summaries" do
        final_job = DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: ["schedule:abc123"],
          active_job_id: "aj-logical-summary",
          finished_at: 1.minute.ago,
          created_at: 3.minutes.ago,
          updated_at: 1.minute.ago,
        )
        final_job.update!(
          arguments: final_job.arguments.merge(
            "continuation" => { "completed" => %w[check_camera_1 check_camera_2] },
            "resumptions"  => 1,
          ),
        )

        run = ::Dashboard::Run.with_execution_associations.find(final_job.id)
        summary = Workflow::LogicalRun.new(jobs: [run], workflow_key: "test_workflow").summary

        assert_equal WORKFLOW_JOB_CLASS_NAME, summary[:class_name]
        assert_equal final_job.id, summary[:job_id]
        assert_equal "finished", summary[:status]
        assert_equal 2, summary[:resumptions]
        assert_equal "test_workflow", summary[:workflow_key]
      end
    end
  end
end

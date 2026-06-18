require "test_helper"

module R3x
  module Dashboard
    class WorkflowSummariesTest < ActiveSupport::TestCase
      WORKFLOW_JOB_CLASS_NAME = DashboardTestWorkflows.ensure_class("TestWorkflow").freeze

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

        summary = Workflow::Summaries.new.find!("test_workflow")

        assert_equal "Healthy", summary[:health][:label]
        assert_predicate summary[:next_trigger_at], :present?
        assert summary[:run_now_available]
        assert_equal 1, summary[:trigger_entries].size
        assert_predicate summary[:trigger_entries].first[:recurring_task], :present?
        assert summary[:trigger_entries].first[:run_now_available]
      end

      test "manual-only direct workflow runs stay visible without trigger metadata" do
        DashboardJobRows.create_job!(
          job_class_name: "Workflows::ManualOnlyWorkflow",
          arguments: [],
          finished_at: 1.minute.ago,
          created_at: 2.minutes.ago,
          updated_at: 1.minute.ago
        )

        summary = Workflow::Summaries.new.find!("manual_only_workflow")

        assert summary[:run_now_available]
        assert_empty summary[:trigger_entries]
        assert_equal "Workflows::ManualOnlyWorkflow", summary[:class_name]
      end

      test "orders the catalog by health severity by default" do
        create_dashboard_workflow(workflow_key: "idle_workflow", trigger_key: "schedule:idle")
        create_dashboard_workflow(
          workflow_key: "healthy_workflow",
          trigger_key: "schedule:healthy",
          run_status: "finished",
          recorded_at: 3.minutes.ago
        )
        create_dashboard_workflow(
          workflow_key: "failed_workflow",
          trigger_key: "schedule:failed",
          run_status: "failed",
          recorded_at: 2.minutes.ago
        )
        summaries = Workflow::Summaries.new.all

        assert_equal %w[failed_workflow healthy_workflow idle_workflow], summaries.map { |summary| summary[:workflow_key] }
      end

      test "reverses health severity order when sorted descending" do
        create_dashboard_workflow(workflow_key: "idle_workflow", trigger_key: "schedule:idle")
        create_dashboard_workflow(
          workflow_key: "healthy_workflow",
          trigger_key: "schedule:healthy",
          run_status: "finished",
          recorded_at: 3.minutes.ago
        )
        create_dashboard_workflow(
          workflow_key: "failed_workflow",
          trigger_key: "schedule:failed",
          run_status: "failed",
          recorded_at: 2.minutes.ago
        )
        summaries = Workflow::Summaries.new(sort: "health", direction: "desc").all

        assert_equal %w[idle_workflow healthy_workflow failed_workflow], summaries.map { |summary| summary[:workflow_key] }
      end

      test "supports workflow and last run sorting" do
        create_dashboard_workflow(
          workflow_key: "zeta_workflow",
          trigger_key: "schedule:zeta",
          run_status: "finished",
          recorded_at: 5.minutes.ago
        )
        create_dashboard_workflow(
          workflow_key: "alpha_workflow",
          trigger_key: "schedule:alpha",
          run_status: "finished",
          recorded_at: 1.minute.ago
        )

        workflow_asc = Workflow::Summaries.new(sort: "workflow", direction: "asc").all
        workflow_desc = Workflow::Summaries.new(sort: "workflow", direction: "desc").all
        last_run_desc = Workflow::Summaries.new(sort: "last_run", direction: "desc").all
        last_run_asc = Workflow::Summaries.new(sort: "last_run", direction: "asc").all

        assert_equal %w[alpha_workflow zeta_workflow], workflow_asc.map { |summary| summary[:workflow_key] }
        assert_equal %w[zeta_workflow alpha_workflow], workflow_desc.map { |summary| summary[:workflow_key] }
        assert_equal %w[alpha_workflow zeta_workflow], last_run_desc.map { |summary| summary[:workflow_key] }
        assert_equal %w[zeta_workflow alpha_workflow], last_run_asc.map { |summary| summary[:workflow_key] }
      end

      test "last run summary follows recorded activity instead of newest enqueue time" do
        job_class_name = DashboardTestWorkflows.ensure_class("OverlapWorkflow")

        SolidQueue::RecurringTask.create!(
          key: "workflow:overlap_workflow:schedule:abc123",
          schedule: "0 * * * *",
          class_name: job_class_name,
          arguments: [ "schedule:abc123" ],
          queue_name: "default",
          static: false
        )

        long_running_job = DashboardJobRows.create_job!(
          job_class_name: job_class_name,
          arguments: [ "schedule:abc123" ],
          created_at: 10.minutes.ago,
          updated_at: 30.seconds.ago
        )
        SolidQueue::FailedExecution.create!(job_id: long_running_job.id, error: "boom", created_at: 30.seconds.ago)

        DashboardJobRows.create_job!(
          job_class_name: job_class_name,
          arguments: [ "schedule:abc123" ],
          finished_at: 2.minutes.ago,
          created_at: 5.minutes.ago,
          updated_at: 2.minutes.ago
        )

        summary = Workflow::Summaries.new.find!("overlap_workflow")

        assert_equal "failed", summary.dig(:last_run, :status)
        assert_equal long_running_job.id, summary.dig(:last_run, :job_id)
        assert_equal "Last run failed", summary.dig(:health, :label)
      end

      test "last run summary counts the final resumed execution" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:schedule:abc123",
          schedule: "0 * * * *",
          class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:abc123" ],
          queue_name: "default",
          static: false
        )

        active_job_id = "aj-summary-finished-after-two-resumes"
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

        summary = Workflow::Summaries.new.find!("test_workflow")

        assert_equal final_job.id, summary.dig(:last_run, :job_id)
        assert_equal 2, summary.dig(:last_run, :resumptions)
      end

      test "builds all summaries without per-workflow run lookups" do
        create_dashboard_workflow(
          workflow_key: "first_workflow",
          trigger_key: "schedule:first",
          run_status: "finished",
          recorded_at: 3.minutes.ago
        )
        create_dashboard_workflow(
          workflow_key: "second_workflow",
          trigger_key: "schedule:second",
          run_status: "failed",
          recorded_at: 1.minute.ago
        )

        Workflow::Runs.stubs(:new).raises("per-workflow run lookup")

        summaries = Workflow::Summaries.new.all

        assert_equal %w[second_workflow first_workflow], summaries.map { |summary| summary[:workflow_key] }
        assert_equal "Last run failed", summaries.first.dig(:health, :label)
      end

      private

      def clear_tables
        TestDbCleanup.clear_runtime_tables!
      end

      def create_dashboard_workflow(workflow_key:, trigger_key:, run_status: nil, recorded_at: nil)
        job_class_name = DashboardTestWorkflows.ensure_class(workflow_key.camelize)

        SolidQueue::RecurringTask.create!(
          key: "workflow:#{workflow_key}:#{trigger_key}",
          schedule: "0 * * * *",
          class_name: job_class_name,
          arguments: [ trigger_key ],
          queue_name: "default",
          static: false
        )

        return if run_status.blank?

        job = DashboardJobRows.create_job!(
          job_class_name: job_class_name,
          arguments: [ trigger_key ],
          finished_at: run_status == "finished" ? recorded_at : nil,
          created_at: recorded_at - 1.minute,
          updated_at: recorded_at
        )

        return unless run_status == "failed"

        SolidQueue::FailedExecution.create!(job_id: job.id, error: "#{workflow_key} failed", created_at: recorded_at)
      end
    end
  end
end

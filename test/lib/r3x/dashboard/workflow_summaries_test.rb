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
        assert summary[:next_trigger_at].present?
        assert summary[:run_now_available]
        assert_equal 1, summary[:trigger_entries].size
        assert summary[:trigger_entries].first[:recurring_task].present?
        assert summary[:trigger_entries].first[:run_now_available]
      end

      test "shows generic run now when only change detection metadata exists" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:feed:abc123",
          schedule: "*/5 * * * *",
          class_name: Workflow::Catalog::CHANGE_DETECTION_CLASS_NAME,
          arguments: [ "test_workflow", { "trigger_key" => "feed:abc123" } ],
          queue_name: "feeds",
          static: false
        )

        summary = Workflow::Summaries.new.find!("test_workflow")

        assert summary[:run_now_available]
        refute summary[:trigger_entries].first[:run_now_available]
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

      test "prefers trigger error health over last run status" do
        R3x::TriggerState.create!(
          workflow_key: "test_dashboard_change_feed",
          trigger_key: "feed:123",
          trigger_type: "fake_change_detecting",
          state: {},
          last_error_at: Time.current,
          last_error_message: "feed offline"
        )

        summary = Workflow::Summaries.new.find!("test_dashboard_change_feed")

        assert_equal "Trigger error", summary[:health][:label]
        assert_equal "feed offline", summary[:health][:detail]
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
        create_dashboard_workflow(
          workflow_key: "trigger_error_workflow",
          trigger_key: "feed:error",
          trigger_error_at: 1.minute.ago
        )

        summaries = Workflow::Summaries.new.all

        assert_equal %w[trigger_error_workflow failed_workflow healthy_workflow idle_workflow], summaries.map { |summary| summary[:workflow_key] }
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
        create_dashboard_workflow(
          workflow_key: "trigger_error_workflow",
          trigger_key: "feed:error",
          trigger_error_at: 1.minute.ago
        )

        summaries = Workflow::Summaries.new(sort: "health", direction: "desc").all

        assert_equal %w[idle_workflow healthy_workflow failed_workflow trigger_error_workflow], summaries.map { |summary| summary[:workflow_key] }
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

      private
        def clear_tables
          TestDbCleanup.clear_runtime_tables!
        end

        def create_dashboard_workflow(workflow_key:, trigger_key:, run_status: nil, recorded_at: nil, trigger_error_at: nil)
          job_class_name = DashboardTestWorkflows.ensure_class(workflow_key.camelize)

          SolidQueue::RecurringTask.create!(
            key: "workflow:#{workflow_key}:#{trigger_key}",
            schedule: "0 * * * *",
            class_name: job_class_name,
            arguments: [ trigger_key ],
            queue_name: "default",
            static: false
          )

          if trigger_error_at.present?
            R3x::TriggerState.create!(
              workflow_key: workflow_key,
              trigger_key: trigger_key,
              trigger_type: "feed",
              state: {},
              last_error_at: trigger_error_at,
              last_error_message: "#{workflow_key} error"
            )
          end

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

require "test_helper"

module R3x
  module Workflow
    class ExecutionTest < ActiveSupport::TestCase
      test "previous_run_at returns nil when no execution in solid_queue" do
        execution = Execution.new(workflow_key: "nonexistent_workflow")
        assert_nil execution.previous_run_at
      end

      test "previous_run_at is memoized" do
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "R3x::RunWorkflowJob",
          arguments: [ "test_memo" ]
        )
        SolidQueue::RecurringTask.create!(
          key: "test_memo",
          schedule: "0 * * * *",
          class_name: "R3x::RunWorkflowJob",
          arguments: [],
          queue_name: "default"
        )
        SolidQueue::RecurringExecution.create!(
          task_key: "test_memo",
          run_at: 2.hours.ago,
          job_id: job.id
        )

        execution = Execution.new(workflow_key: "test_memo")

        t1 = execution.previous_run_at
        t2 = execution.previous_run_at

        assert_equal t1, t2
        assert t1.present?
      ensure
        SolidQueue::RecurringExecution.where(task_key: "test_memo").delete_all
        SolidQueue::RecurringTask.where(key: "test_memo").delete_all
        SolidQueue::Job.where(class_name: "R3x::RunWorkflowJob").delete_all
      end

      test "first_run? returns true when no previous_run_at" do
        execution = Execution.new(workflow_key: "new_workflow")
        assert execution.first_run?
      end

      test "first_run? returns false when previous_run_at exists" do
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: "R3x::RunWorkflowJob",
          arguments: [ "test_fr" ]
        )
        SolidQueue::RecurringTask.create!(
          key: "test_fr",
          schedule: "0 * * * *",
          class_name: "R3x::RunWorkflowJob",
          arguments: [],
          queue_name: "default"
        )
        SolidQueue::RecurringExecution.create!(
          task_key: "test_fr",
          run_at: 2.hours.ago,
          job_id: job.id
        )

        execution = Execution.new(workflow_key: "test_fr")
        refute execution.first_run?
      ensure
        SolidQueue::RecurringExecution.where(task_key: "test_fr").delete_all
        SolidQueue::RecurringTask.where(key: "test_fr").delete_all
        SolidQueue::Job.where(class_name: "R3x::RunWorkflowJob").delete_all
      end
    end

    class ContextTest < ActiveSupport::TestCase
      test "has trigger and execution" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        trigger_execution = R3x::TriggerManager::Execution.new(trigger: trigger, workflow_key: "test")
        ctx = Context.new(trigger: trigger_execution, workflow_key: "test")

        assert_equal :schedule, ctx.trigger.type
        assert ctx.trigger.schedule?
        assert ctx.execution.is_a?(Execution)
      end

      test "client proxy builds gmail output from credentials env" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        trigger_execution = R3x::TriggerManager::Execution.new(trigger: trigger, workflow_key: "test")
        ctx = Context.new(trigger: trigger_execution, workflow_key: "test")
        gmail = ctx.client.gmail(credentials_env: "GOOGLE_CREDENTIALS_MISSING")

        assert_instance_of R3x::Outputs::Gmail, gmail
        assert_equal({ "mode" => "dry-run" }, gmail.deliver(to: "recipient@example.com", subject: "Hello", body: "Body"))
      end

      test "client proxy builds google sheets client from credentials env" do
        captured = nil
        fake_client = Object.new
        singleton_class = R3x::Client::GoogleSheets.singleton_class
        original_method = R3x::Client::GoogleSheets.method(:new)

        singleton_class.define_method(:new) do |**kwargs|
          captured = kwargs
          fake_client
        end

        sheets = Context.new(
          trigger: R3x::TriggerManager::Execution.new(
            trigger: R3x::Triggers::Schedule.new(cron: "0 13 * * *"),
            workflow_key: "test"
          ),
          workflow_key: "test"
        ).client.google_sheets(
          spreadsheet_id: "spreadsheet-123",
          credentials_env: "GOOGLE_CREDENTIALS_TEST_APP"
        )

        assert_same fake_client, sheets
        assert_equal(
          {
            spreadsheet_id: "spreadsheet-123",
            credentials_env: "GOOGLE_CREDENTIALS_TEST_APP"
          },
          captured
        )
      ensure
        singleton_class.define_method(:new, original_method)
      end
    end
  end
end

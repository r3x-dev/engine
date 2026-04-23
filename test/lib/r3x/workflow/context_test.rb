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

      test "client proxy builds gmail client from project" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        trigger_execution = R3x::TriggerManager::Execution.new(trigger: trigger, workflow_key: "test")
        ctx = Context.new(trigger: trigger_execution, workflow_key: "test")
        gmail = ctx.client.gmail(project: "MISSING")

        assert_instance_of R3x::Client::Google::Gmail, gmail
      end

      test "client proxy builds google translate client from project" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        trigger_execution = R3x::TriggerManager::Execution.new(trigger: trigger, workflow_key: "test")
        ctx = Context.new(trigger: trigger_execution, workflow_key: "test")
        translate = ctx.client.google_translate(project: "MISSING")

        assert_instance_of R3x::Client::Google::Translate, translate
      end

      test "client proxy builds discord webhook client" do
        with_env("DISCORD_WEBHOOK_URL_TEST" => "https://discord.test/webhook") do
          ctx = Context.new(
            trigger: R3x::TriggerManager::Execution.new(
              trigger: R3x::Triggers::Schedule.new(cron: "0 13 * * *"),
              workflow_key: "test"
            ),
            workflow_key: "test"
          )
          discord = ctx.client.discord(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST")

          assert_instance_of R3x::Client::Discord, discord
        end
      end

      private

      def with_env(hash)
        originals = hash.each_with_object({}) { |(k, _), memo| memo[k] = ENV[k] }
        hash.each { |k, v| ENV[k] = v }
        yield
      ensure
        originals.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end
    end
  end
end

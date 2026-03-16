require "test_helper"

module R3x
  class TriggerExecutionTest < ActiveSupport::TestCase
    test "delegates type to trigger" do
      trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
      execution = TriggerExecution.new(trigger: trigger, workflow_key: "test")
      assert_equal :schedule, execution.type
    end

    test "dynamic schedule? predicate" do
      trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
      execution = TriggerExecution.new(trigger: trigger, workflow_key: "test")
      assert execution.schedule?
      refute execution.manual?
    end

    test "dynamic manual? predicate" do
      trigger = R3x::Triggers::Manual.new
      execution = TriggerExecution.new(trigger: trigger, workflow_key: "test")
      refute execution.schedule?
      assert execution.manual?
    end

    test "delegates options to trigger" do
      trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
      execution = TriggerExecution.new(trigger: trigger, workflow_key: "test")
      assert_equal({ cron: "0 13 * * *" }, execution.options)
    end
  end

  class WorkflowExecutionTest < ActiveSupport::TestCase
    test "previous_run_at returns nil when no execution in solid_queue" do
      execution = WorkflowExecution.new(workflow_key: "nonexistent_workflow")
      assert_nil execution.previous_run_at
    end

    test "previous_run_at is memoized" do
      # Setup test data
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

      execution = WorkflowExecution.new(workflow_key: "test_memo")

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
      execution = WorkflowExecution.new(workflow_key: "new_workflow")
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

      execution = WorkflowExecution.new(workflow_key: "test_fr")
      refute execution.first_run?
    ensure
      SolidQueue::RecurringExecution.where(task_key: "test_fr").delete_all
      SolidQueue::RecurringTask.where(key: "test_fr").delete_all
      SolidQueue::Job.where(class_name: "R3x::RunWorkflowJob").delete_all
    end
  end

  class WorkflowContextTest < ActiveSupport::TestCase
    test "has trigger and execution" do
      trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
      trigger_execution = TriggerExecution.new(trigger: trigger, workflow_key: "test")
      ctx = WorkflowContext.new(trigger: trigger_execution, workflow_key: "test")

      assert_equal :schedule, ctx.trigger.type
      assert ctx.trigger.schedule?
      assert ctx.execution.is_a?(WorkflowExecution)
    end
  end
end

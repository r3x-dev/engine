# frozen_string_literal: true

require "test_helper"

class Dashboard::RecurringTaskTest < ActiveSupport::TestCase
  setup do
    TestDbCleanup.clear_runtime_tables!
  end

  teardown do
    TestDbCleanup.clear_runtime_tables!
  end

  test "parses workflow and trigger keys for recurring workflow tasks" do
    task = Dashboard::RecurringTask.create!(
      key: "workflow:test_workflow:schedule:123",
      schedule: "0 * * * *",
      class_name: "Workflows::TestWorkflow",
      arguments: ["schedule:123"],
      queue_name: "default",
      static: false,
    )

    assert_equal "test_workflow", task.workflow_key
    assert_equal "schedule:123", task.trigger_key
    assert_equal "Workflows::TestWorkflow", task.direct_workflow_class_name
  end

  test "workflow key lookup matches literal underscores and percents" do
    Dashboard::RecurringTask.create!(
      key: "workflow:foo_bar:schedule:1",
      schedule: "0 * * * *",
      class_name: "Workflows::FooBar",
      arguments: ["schedule:1"],
      static: false,
    )
    Dashboard::RecurringTask.create!(
      key: "workflow:foo1bar:schedule:1",
      schedule: "0 * * * *",
      class_name: "Workflows::Foo1bar",
      arguments: ["schedule:1"],
      static: false,
    )
    Dashboard::RecurringTask.create!(
      key: "workflow:foo%bar:schedule:1",
      schedule: "0 * * * *",
      class_name: "Workflows::FooPercentBar",
      arguments: ["schedule:1"],
      static: false,
    )
    Dashboard::RecurringTask.create!(
      key: "workflow:fooxbar:schedule:1",
      schedule: "0 * * * *",
      class_name: "Workflows::FooXbar",
      arguments: ["schedule:1"],
      static: false,
    )

    assert_equal ["workflow:foo_bar:schedule:1"], Dashboard::RecurringTask.for_workflow_key("foo_bar").pluck(:key)
    assert_equal ["workflow:foo%bar:schedule:1"], Dashboard::RecurringTask.for_workflow_key("foo%bar").pluck(:key)
  end

  test "preferred_for_workflow returns a matching recurring workflow task" do
    task = Dashboard::RecurringTask.create!(
      key: "workflow:test_workflow:schedule:123",
      schedule: "0 * * * *",
      class_name: "Workflows::TestWorkflow",
      arguments: ["schedule:123"],
      queue_name: "default",
      static: false,
    )

    assert_equal task, Dashboard::RecurringTask.preferred_for_workflow("test_workflow")
    assert_equal task, Dashboard::RecurringTask.find_by_workflow_and_trigger_key!(workflow_key: "test_workflow", trigger_key: "schedule:123")
  end
end

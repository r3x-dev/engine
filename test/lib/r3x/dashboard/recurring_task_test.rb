require "test_helper"

class Dashboard::RecurringTaskTest < ActiveSupport::TestCase
  setup do
    TestDbCleanup.clear_runtime_tables!
  end

  teardown do
    TestDbCleanup.clear_runtime_tables!
  end

  test "parses workflow and trigger keys for direct and change-detection tasks" do
    direct_task = Dashboard::RecurringTask.create!(
      key: "workflow:test_workflow:schedule:123",
      schedule: "0 * * * *",
      class_name: "Workflows::TestWorkflow",
      arguments: [ "schedule:123" ],
      queue_name: "default",
      static: false
    )
    change_detection_task = Dashboard::RecurringTask.create!(
      key: "workflow:feed_watch:feed:123",
      schedule: "*/5 * * * *",
      class_name: Dashboard::RecurringTask::CHANGE_DETECTION_CLASS_NAME,
      arguments: [ "feed_watch", { "trigger_key" => "feed:123" } ],
      queue_name: "feeds",
      static: false
    )

    assert_equal "test_workflow", direct_task.workflow_key
    assert_equal "schedule:123", direct_task.trigger_key
    assert_equal "Workflows::TestWorkflow", direct_task.direct_workflow_class_name
    refute direct_task.change_detection?

    assert_equal "feed_watch", change_detection_task.workflow_key
    assert_equal "feed:123", change_detection_task.trigger_key
    assert_nil change_detection_task.direct_workflow_class_name
    assert change_detection_task.change_detection?
  end

  test "workflow key lookup matches literal underscores and percents" do
    Dashboard::RecurringTask.create!(
      key: "workflow:foo_bar:schedule:1",
      schedule: "0 * * * *",
      class_name: "Workflows::FooBar",
      arguments: [ "schedule:1" ],
      static: false
    )
    Dashboard::RecurringTask.create!(
      key: "workflow:foo1bar:schedule:1",
      schedule: "0 * * * *",
      class_name: "Workflows::Foo1bar",
      arguments: [ "schedule:1" ],
      static: false
    )
    Dashboard::RecurringTask.create!(
      key: "workflow:foo%bar:schedule:1",
      schedule: "0 * * * *",
      class_name: "Workflows::FooPercentBar",
      arguments: [ "schedule:1" ],
      static: false
    )
    Dashboard::RecurringTask.create!(
      key: "workflow:fooxbar:schedule:1",
      schedule: "0 * * * *",
      class_name: "Workflows::FooXbar",
      arguments: [ "schedule:1" ],
      static: false
    )

    assert_equal [ "workflow:foo_bar:schedule:1" ], Dashboard::RecurringTask.for_workflow_key("foo_bar").pluck(:key)
    assert_equal [ "workflow:foo%bar:schedule:1" ], Dashboard::RecurringTask.for_workflow_key("foo%bar").pluck(:key)
  end

  test "preferred_for_workflow prefers direct workflow classes over change detection tasks" do
    change_detection_task = Dashboard::RecurringTask.create!(
      key: "workflow:test_workflow:feed:123",
      schedule: "*/5 * * * *",
      class_name: Dashboard::RecurringTask::CHANGE_DETECTION_CLASS_NAME,
      arguments: [ "test_workflow", { "trigger_key" => "feed:123" } ],
      queue_name: "feeds",
      static: false
    )
    direct_task = Dashboard::RecurringTask.create!(
      key: "workflow:test_workflow:schedule:123",
      schedule: "0 * * * *",
      class_name: "Workflows::TestWorkflow",
      arguments: [ "schedule:123" ],
      queue_name: "default",
      static: false
    )

    assert_equal direct_task, Dashboard::RecurringTask.preferred_for_workflow("test_workflow")
    assert_equal change_detection_task, Dashboard::RecurringTask.find_by_workflow_and_trigger_key!(workflow_key: "test_workflow", trigger_key: "feed:123")
  end
end

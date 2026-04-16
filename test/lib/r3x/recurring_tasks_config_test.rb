require "test_helper"
require_relative "../../support/fake_change_detecting_trigger"

module R3x
  class RecurringTasksConfigTest < ActiveSupport::TestCase
    setup do
      @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
      @original_timezone = ENV["R3X_TIMEZONE"]
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
      R3x::Workflow::PackLoader.load!(force: true)
    end

    teardown do
      ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
      ENV["R3X_TIMEZONE"] = @original_timezone
      SolidQueue::RecurringTask.dynamic.where("key LIKE 'workflow:test_workflow:%'").delete_all
    end

    test "generates recurring tasks from workflow DSL" do
      ENV.delete("R3X_TIMEZONE")

      tasks = RecurringTasksConfig.to_h

      expected_key = "workflow:test_workflow:schedule:"
      task = tasks.find { |k, _| k.start_with?(expected_key) }&.last

      assert task, "Expected task with key starting with #{expected_key}"
      assert_equal "Workflows::TestWorkflow", task["class"]
      assert_equal "0 * * * *", task["schedule"]
      assert_equal "default", task["queue"]
    end

    test "only includes workflows with schedule triggers" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NoSchedule"
        end
      end

      R3x::Workflow::Registry.register(workflow_class)

      tasks = RecurringTasksConfig.to_h
      refute tasks.key?("no_schedule")

      Workflow::Registry.reset!
    end

    test "generates change detection tasks for change-detecting triggers" do
      fake_trigger = R3x::TestSupport::FakeChangeDetectingTrigger.new(identity: "feed")
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ChangeDetectingFeed"
        end

        define_singleton_method(:triggers) { [ fake_trigger ] }
        define_singleton_method(:schedulable_triggers) { [ fake_trigger ] }
      end

      R3x::Workflow::Registry.register(workflow_class)

      tasks = RecurringTasksConfig.to_h
      expected_key = "workflow:change_detecting_feed:#{fake_trigger.unique_key}"
      task = tasks.fetch(expected_key)

      assert_equal "R3x::ChangeDetectionJob", task["class"]
      assert_equal [ "change_detecting_feed", { "trigger_key" => fake_trigger.unique_key } ], task["args"]
      assert_equal "every 15 minutes", task["schedule"]
      assert_equal "default", task["queue"]
    ensure
      Workflow::Registry.reset!
      Workflow::PackLoader.load!(force: true)
    end

    test "schedule_all! persists dynamic tasks via SolidQueue" do
      ENV.delete("R3X_TIMEZONE")

      RecurringTasksConfig.schedule_all!

      dynamic_tasks = SolidQueue::RecurringTask.dynamic.where("key LIKE 'workflow:test_workflow:%'")
      assert dynamic_tasks.any?, "Expected dynamic tasks to be created"

      task = dynamic_tasks.find { |t| t.key.include?(":schedule:") }
      assert task, "Expected a schedule trigger task"
      assert_equal "Workflows::TestWorkflow", task.class_name
      assert_equal "0 * * * *", task.schedule
    end

    test "schedule_all! logs workflow and trigger context" do
      ENV.delete("R3X_TIMEZONE")
      workflow_class = R3x::Workflow::Registry.fetch("test_workflow")
      schedule_trigger = workflow_class.schedulable_triggers.first

      output = capture_logged_output do
        RecurringTasksConfig.schedule_all!
      end

      assert_includes output, "R3x::RecurringTasksConfig"
      assert_includes output, "r3x.workflow_key=test_workflow"
      assert_includes output, "r3x.trigger_key=#{schedule_trigger.unique_key}"
      assert_includes output, "Scheduled recurring task"
    end

    test "to_h appends timezone to schedule when trigger declares one" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::TimezoneAware"
        end

        trigger :schedule, cron: "0 13 * * *", timezone: "Europe/Paris"
      end

      R3x::Workflow::Registry.register(workflow_class)

      task = RecurringTasksConfig.to_h.values.find { |entry| entry["class"] == "Workflows::TimezoneAware" }

      assert task
      assert_equal "0 13 * * * Europe/Paris", task["schedule"]
    ensure
      Workflow::Registry.reset!
      Workflow::PackLoader.load!(force: true)
    end

    test "to_h uses default timezone env for schedules without explicit timezone" do
      ENV["R3X_TIMEZONE"] = "UTC"

      tasks = RecurringTasksConfig.to_h
      expected_key = "workflow:test_workflow:schedule:"
      task = tasks.find { |k, _| k.start_with?(expected_key) }&.last

      assert task, "Expected task with key starting with #{expected_key}"
      assert_equal "0 * * * * UTC", task["schedule"]
    end

    test "to_h keeps embedded cron timezone without appending env timezone" do
      ENV["R3X_TIMEZONE"] = "UTC"

      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::EmbeddedTimezone"
        end

        trigger :schedule, cron: "0 13 * * * Europe/Paris"
      end

      R3x::Workflow::Registry.register(workflow_class)

      task = RecurringTasksConfig.to_h.values.find { |entry| entry["class"] == "Workflows::EmbeddedTimezone" }

      assert task
      assert_equal "0 13 * * * Europe/Paris", task["schedule"]
    ensure
      Workflow::Registry.reset!
      Workflow::PackLoader.load!(force: true)
    end

    test "schedule_all! removes stale dynamic tasks" do
      SolidQueue.schedule_recurring_task(
        "workflow:test_workflow:stale_trigger",
        class: "R3x::RunWorkflowJob",
        args: [ "test_workflow", { "trigger_key" => "stale" } ],
        schedule: "0 * * * *"
      )

      assert SolidQueue::RecurringTask.dynamic.find_by(key: "workflow:test_workflow:stale_trigger")

      RecurringTasksConfig.schedule_all!

      refute SolidQueue::RecurringTask.dynamic.find_by(key: "workflow:test_workflow:stale_trigger")
    end

    test "schedule_all! is idempotent" do
      RecurringTasksConfig.schedule_all!
      first_count = SolidQueue::RecurringTask.dynamic.where("key LIKE 'workflow:test_workflow:%'").count

      RecurringTasksConfig.schedule_all!
      second_count = SolidQueue::RecurringTask.dynamic.where("key LIKE 'workflow:test_workflow:%'").count

      assert_equal first_count, second_count
    end

    test "schedule_all! does not delete foreign dynamic tasks" do
      SolidQueue.schedule_recurring_task(
        "foreign_system:task",
        class: "R3x::RunWorkflowJob",
        args: [ "test_workflow", { "trigger_key" => "foreign" } ],
        schedule: "0 * * * *"
      )

      RecurringTasksConfig.schedule_all!

      assert SolidQueue::RecurringTask.dynamic.find_by(key: "foreign_system:task")
    ensure
      SolidQueue::RecurringTask.dynamic.where(key: "foreign_system:task").delete_all
    end
  end
end

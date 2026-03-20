require "test_helper"
require_relative "../../support/fake_change_detecting_trigger"

module R3x
  class RecurringTasksConfigTest < ActiveSupport::TestCase
    setup do
      @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
      WorkflowPackLoader.load!(force: true)
    end

    teardown do
      ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
    end

    test "generates recurring tasks from workflow DSL" do
      tasks = RecurringTasksConfig.to_h

      expected_key = "test_workflow:schedule:"
      task = tasks.find { |k, _| k.start_with?(expected_key) }&.last

      assert task, "Expected task with key starting with #{expected_key}"
      assert_equal "R3x::RunWorkflowJob", task["class"]
      assert_equal "0 * * * *", task["schedule"]
      assert_equal "default", task["queue"]
    end

    test "only includes workflows with schedule triggers" do
      # Create a workflow without schedule trigger
      workflow_class = Class.new(R3x::Workflow) do
        def self.name
          "Workflows::NoSchedule"
        end
      end

      WorkflowRegistry.register(workflow_class)

      tasks = RecurringTasksConfig.to_h
      refute tasks.key?("no_schedule")

      # Cleanup
      WorkflowRegistry.reset!
      WorkflowPackLoader.load!(force: true)
    end

    test "generates change detection tasks for change-detecting triggers" do
      fake_trigger = R3x::TestSupport::FakeChangeDetectingTrigger.new(identity: "feed")
      workflow_class = Class.new(R3x::Workflow) do
        def self.name
          "Workflows::ChangeDetectingFeed"
        end

        define_singleton_method(:triggers) { [ fake_trigger ] }
        define_singleton_method(:schedulable_triggers) { [ fake_trigger ] }
      end

      WorkflowRegistry.register(workflow_class)

      tasks = RecurringTasksConfig.to_h
      expected_key = "change_detecting_feed:#{fake_trigger.unique_key}"
      task = tasks.fetch(expected_key)

      assert_equal "R3x::ChangeDetectionJob", task["class"]
      assert_equal [ "change_detecting_feed", { "trigger_key" => fake_trigger.unique_key } ], task["args"]
      assert_equal "every 15 minutes", task["schedule"]
      assert_equal "default", task["queue"]
    ensure
      WorkflowRegistry.reset!
      WorkflowPackLoader.load!(force: true)
    end
  end
end

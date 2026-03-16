require "test_helper"
require "r3x/recurring_tasks_config"

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

      assert tasks.key?("test_workflow")
      task = tasks["test_workflow"]

      assert_equal "R3x::RunWorkflowJob", task["class"]
      assert_equal [ "test_workflow", { "triggered_by" => "schedule" } ], task["args"]
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
  end
end

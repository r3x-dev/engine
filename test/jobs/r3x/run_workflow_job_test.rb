require "test_helper"

module R3x
  class RunWorkflowJobTest < ActiveSupport::TestCase
    setup do
      @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
      WorkflowPackLoader.load!(force: true)
    end

    teardown do
      ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
    end

    test "performs workflow with manual trigger when no triggered_by provided" do
      job = RunWorkflowJob.new

      # The test_workflow is already loaded from fixtures and has a simple run method
      result = job.perform("test_workflow")

      assert_equal true, result["test"]
      assert_equal "Test workflow executed successfully", result["message"]
    end

    test "performs workflow with schedule trigger" do
      job = RunWorkflowJob.new

      # Create a test workflow class that checks trigger
      test_workflow_class = Class.new(R3x::Workflow) do
        def self.name
          "TestTriggerType"
        end

        trigger :schedule, cron: "0 * * * *"

        def run(ctx)
          {
            "trigger_type" => ctx.trigger.type.to_s,
            "schedule?" => ctx.trigger.schedule?
          }
        end
      end

      WorkflowRegistry.register(test_workflow_class)

      result = job.perform("test_trigger_type", trigger_type: "schedule")

      assert_equal "schedule", result["trigger_type"]
      assert result["schedule?"]
    ensure
      WorkflowRegistry.reset!
      WorkflowPackLoader.load!(force: true)
    end

    test "performs workflow with manual trigger explicitly" do
      job = RunWorkflowJob.new

      test_workflow_class = Class.new(R3x::Workflow) do
        def self.name
          "TestManual"
        end

        trigger :manual

        def run(ctx)
          {
            "trigger_type" => ctx.trigger.type.to_s,
            "schedule?" => ctx.trigger.schedule?
          }
        end
      end

      WorkflowRegistry.register(test_workflow_class)

      result = job.perform("test_manual", trigger_type: "manual")

      assert_equal "manual", result["trigger_type"]
      refute result["schedule?"]
    ensure
      WorkflowRegistry.reset!
      WorkflowPackLoader.load!(force: true)
    end
  end
end

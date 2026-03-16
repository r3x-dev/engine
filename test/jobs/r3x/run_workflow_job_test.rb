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

      # Create a test workflow class that checks triggered_by
      test_workflow_class = Class.new(R3x::Workflow) do
        def self.name
          "TestTriggeredBy"
        end

        def run(ctx)
          {
            "triggered_by_type" => ctx.triggered_by.type.to_s,
            "schedule?" => ctx.triggered_by.schedule?,
            "manual?" => ctx.triggered_by.manual?
          }
        end
      end

      WorkflowRegistry.register(test_workflow_class)

      result = job.perform("test_triggered_by", triggered_by: "schedule")

      assert_equal "schedule", result["triggered_by_type"]
      assert result["schedule?"]
      refute result["manual?"]
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

        def run(ctx)
          {
            "triggered_by_type" => ctx.triggered_by.type.to_s,
            "schedule?" => ctx.triggered_by.schedule?,
            "manual?" => ctx.triggered_by.manual?
          }
        end
      end

      WorkflowRegistry.register(test_workflow_class)

      result = job.perform("test_manual", triggered_by: "manual")

      assert_equal "manual", result["triggered_by_type"]
      refute result["schedule?"]
      assert result["manual?"]
    ensure
      WorkflowRegistry.reset!
      WorkflowPackLoader.load!(force: true)
    end
  end
end

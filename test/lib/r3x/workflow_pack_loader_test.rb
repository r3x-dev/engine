require "test_helper"

module R3x
  class WorkflowPackLoaderTest < ActiveSupport::TestCase
    setup do
      @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
      R3x::Workflow::PackLoader.load!(force: true)
    end

    teardown do
      ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
    end

    test "loads workflow from external path by convention" do
      workflow_class = R3x::Workflow::Registry.fetch("test_workflow")

      assert_equal Workflows::TestWorkflow, workflow_class
      assert_equal "test_workflow", workflow_class.workflow_key

      schedule = workflow_class.schedulable_triggers.first
      assert schedule
      assert_equal :schedule, schedule.type
      assert_equal "0 * * * *", schedule.cron
      assert_nil schedule.timezone
      assert_equal "0 * * * *", schedule.schedule
    end

    test "raises KeyError for unknown workflow" do
      assert_raises(KeyError) do
        R3x::Workflow::Registry.fetch("unknown_workflow")
      end
    end

    test "can run loaded workflow" do
      workflow_class = R3x::Workflow::Registry.fetch("test_workflow")
      result = workflow_class.new.run

      assert_equal true, result["test"]
      assert_equal "Test workflow executed successfully", result["message"]
    end

    test "logs loaded workflows with workflow tags" do
      output = capture_logged_output do
        R3x::Workflow::PackLoader.load!(force: true)
      end

      assert_includes output, "R3x::Workflow::PackLoader"
      assert_includes output, "r3x.workflow_key=test_workflow"
      assert_includes output, "Loaded workflow class=Workflows::TestWorkflow"
    end
  end
end

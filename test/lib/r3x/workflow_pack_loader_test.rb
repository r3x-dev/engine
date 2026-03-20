require "test_helper"

module R3x
  class R3x::Workflow::PackLoaderTest < ActiveSupport::TestCase
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
    end

    test "raises KeyError for unknown workflow" do
      assert_raises(KeyError) do
        R3x::Workflow::Registry.fetch("unknown_workflow")
      end
    end

    test "can run loaded workflow" do
      workflow_class = R3x::Workflow::Registry.fetch("test_workflow")
      trigger = R3x::Triggers::Manual.new
      execution = R3x::TriggerManager::Execution.new(
        trigger: trigger,
        workflow_key: "test_workflow"
      )
      ctx = R3x::Workflow::Context.new(
        trigger: execution,
        workflow_key: "test_workflow"
      )
      result = workflow_class.new.run(ctx)

      assert_equal true, result["test"]
      assert_equal "Test workflow executed successfully", result["message"]
    end
  end
end

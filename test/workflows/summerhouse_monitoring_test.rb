require "test_helper"

module Workflows
  class SummerhouseMonitoringTest < ActiveSupport::TestCase
    setup do
      @original = ENV["R3X_WORKFLOW_PATHS"]
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("workflows").to_s
      R3x::Workflow::PackLoader.load!(force: true)
    end

    teardown do
      ENV["R3X_WORKFLOW_PATHS"] = @original
      R3x::Workflow::PackLoader.load!(force: true)
    end

    test "declares manual and schedule triggers" do
      wf = R3x::Workflow::Registry.fetch("summerhouse_monitoring")
      assert_equal 2, wf.triggers.size
      assert_equal :manual, wf.triggers[0].type
      assert_equal :schedule, wf.triggers[1].type
      assert_equal "0 12 * * *", wf.triggers[1].cron
    end

    test "declares networking and llm capabilities" do
      wf = R3x::Workflow::Registry.fetch("summerhouse_monitoring")
      assert wf.uses?(:networking)
      assert wf.uses?(:llm)
      assert_equal({ api_key_env: "GEMINI_API_KEY_MICHAL" }, wf.llm_config)
    end

    test "workflow_key is summerhouse_monitoring" do
      wf = R3x::Workflow::Registry.fetch("summerhouse_monitoring")
      assert_equal "summerhouse_monitoring", wf.workflow_key
    end
  end
end

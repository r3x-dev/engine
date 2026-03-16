require "test_helper"

module R3x
  class WorkflowContextTest < ActiveSupport::TestCase
    test "defaults to manual trigger when no triggered_by provided" do
      ctx = WorkflowContext.new
      assert ctx.triggered_by.manual?
    end

    test "accepts TriggeredBy object" do
      triggered_by = TriggeredBy.new(:schedule)
      ctx = WorkflowContext.new(triggered_by: triggered_by)
      assert ctx.triggered_by.schedule?
    end

    test "schedule trigger detection" do
      ctx = WorkflowContext.new(triggered_by: TriggeredBy.new(:schedule))
      assert ctx.triggered_by.schedule?
      refute ctx.triggered_by.manual?
    end
  end
end

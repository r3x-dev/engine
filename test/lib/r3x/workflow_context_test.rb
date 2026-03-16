require "test_helper"

module R3x
  class WorkflowContextTest < ActiveSupport::TestCase
    test "requires triggered_by" do
      assert_raises(ArgumentError) do
        WorkflowContext.build
      end
    end

    test "defaults to manual trigger via builder" do
      ctx = WorkflowContext.build do |b|
        b.triggered_by = TriggeredBy.new(:manual)
      end
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

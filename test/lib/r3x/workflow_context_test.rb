require "test_helper"

module R3x
  class TriggerInfoTest < ActiveSupport::TestCase
    test "converts type to symbol" do
      trigger = R3x::TriggerInfo.new("schedule")
      assert_equal :schedule, trigger.type
    end

    test "schedule? returns true for schedule type" do
      trigger = R3x::TriggerInfo.new(:schedule)
      assert trigger.schedule?
      refute trigger.manual?
    end

    test "manual? returns true for manual type" do
      trigger = R3x::TriggerInfo.new(:manual)
      refute trigger.schedule?
      assert trigger.manual?
    end

    test "previous_run_at returns nil for non-schedule trigger" do
      trigger = R3x::TriggerInfo.new(:manual, previous_run_at_fetcher: -> { Time.current })
      assert_nil trigger.previous_run_at
    end

    test "previous_run_at is memoized" do
      call_count = 0
      fetcher = -> {
        call_count += 1
        Time.current
      }
      trigger = R3x::TriggerInfo.new(:schedule, previous_run_at_fetcher: fetcher)

      t1 = trigger.previous_run_at
      t2 = trigger.previous_run_at

      assert_equal t1, t2
      assert_equal 1, call_count
    end

    test "first_run? returns true when no previous_run_at" do
      trigger = R3x::TriggerInfo.new(:schedule)
      assert trigger.first_run?
    end

    test "first_run? returns false when previous_run_at exists" do
      trigger = R3x::TriggerInfo.new(:schedule, previous_run_at_fetcher: -> { Time.current })
      refute trigger.first_run?
    end
  end

  class WorkflowContextTest < ActiveSupport::TestCase
    test "requires trigger_type" do
      assert_raises(ArgumentError) do
        WorkflowContext.build
      end
    end

    test "accepts trigger_type as string" do
      ctx = WorkflowContext.build do |b|
        b.trigger_type = "schedule"
      end
      assert_equal :schedule, ctx.trigger.type
      assert ctx.trigger.schedule?
    end

    test "accepts trigger_type as symbol" do
      ctx = WorkflowContext.build do |b|
        b.trigger_type = :manual
      end
      assert_equal :manual, ctx.trigger.type
      assert ctx.trigger.manual?
    end
  end
end

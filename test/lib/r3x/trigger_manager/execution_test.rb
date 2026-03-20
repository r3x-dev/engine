require "test_helper"

module R3x
  module TriggerManager
    class ExecutionTest < ActiveSupport::TestCase
      test "delegates type to trigger" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        execution = Execution.new(trigger: trigger, workflow_key: "test")
        assert_equal :schedule, execution.type
      end

      test "dynamic schedule? predicate" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        execution = Execution.new(trigger: trigger, workflow_key: "test")
        assert execution.schedule?
        refute execution.manual?
      end

      test "dynamic manual? predicate" do
        trigger = R3x::Triggers::Manual.new
        execution = Execution.new(trigger: trigger, workflow_key: "test")
        refute execution.schedule?
        assert execution.manual?
      end

      test "delegates options to trigger" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        execution = Execution.new(trigger: trigger, workflow_key: "test")
        assert_equal({ cron: "0 13 * * *" }, execution.options)
      end

      test "exposes runtime payload" do
        trigger = R3x::Triggers::Manual.new
        execution = Execution.new(
          trigger: trigger,
          workflow_key: "test",
          payload: { "entries" => [ { "title" => "Hello" } ] }
        )

        assert_equal({ "entries" => [ { "title" => "Hello" } ] }, execution.payload)
      end
    end
  end
end

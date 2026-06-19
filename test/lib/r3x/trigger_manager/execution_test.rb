# frozen_string_literal: true

require "test_helper"

module R3x
  module TriggerManager
    class ExecutionTest < ActiveSupport::TestCase
      test "delegates type to trigger" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        execution = Execution.new(trigger:, workflow_key: "test")

        assert_equal :schedule, execution.type
      end

      test "schedule? predicate" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        execution = Execution.new(trigger:, workflow_key: "test")

        assert_predicate execution, :schedule?
        assert_not_predicate execution, :manual?
      end

      test "manual? predicate" do
        trigger = R3x::Triggers::Manual.new
        execution = Execution.new(trigger:, workflow_key: "test")

        assert_not_predicate execution, :schedule?
        assert_predicate execution, :manual?
      end

      test "does not synthesize unknown trigger predicates" do
        trigger = R3x::Triggers::Manual.new
        execution = Execution.new(trigger:, workflow_key: "test")

        assert_not_respond_to execution, :webhook?
        assert_raises(NoMethodError) { execution.webhook? }
      end

      test "delegates options to trigger" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        execution = Execution.new(trigger:, workflow_key: "test")

        assert_equal({ cron: "0 13 * * *" }, execution.options)
      end

      test "exposes runtime payload" do
        trigger = R3x::Triggers::Manual.new
        execution = Execution.new(
          trigger:,
          workflow_key: "test",
          payload: { "entries" => [{ "title" => "Hello" }] }
        )

        assert_equal({ "entries" => [{ "title" => "Hello" }] }, execution.payload)
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/workflows/stable_trigger_workflow/workflow"

module R3x
  module Workflow
    class StableTriggerTest < ActiveSupport::TestCase
      setup do
        TestDbCleanup.clear_runtime_tables!
        @workflow = Workflows::StableTriggerWorkflow
        @original_triggers = @workflow._triggers
        @workflow::EVENTS.clear
      end

      teardown do
        @workflow._triggers = @original_triggers
        @workflow::EVENTS.clear
        TestDbCleanup.clear_runtime_tables!
      end

      test "queued and resumed jobs survive schedule changes and trigger reordering" do
        Registry.stubs(:all).returns([@workflow])
        RecurringTasksConfig.schedule_all!
        task = SolidQueue::RecurringTask.find_by!(class_name: @workflow.name)
        trigger_key = @workflow.triggers.first.unique_key
        queued_payload = SolidQueue::Job.enqueue(@workflow.new(trigger_key)).arguments
        started = @workflow.new(trigger_key)

        assert_raises(ActiveJob::Continuation::Interrupt) { started.perform(trigger_key) }
        resumed_payload = MultiJSON.parse(MultiJSON.generate(started.serialize))

        @workflow._triggers = TriggerManager::Collection.new
        @workflow.trigger(:schedule, key: :weekly, cron: "0 10 * * 1")
        @workflow.trigger(:schedule, key: :daily, cron: "0 9 * * *", timezone: "Europe/Warsaw")
        RecurringTasksConfig.schedule_all!

        task.reload

        assert_equal "0 9 * * * Europe/Warsaw", task.schedule
        assert_equal [trigger_key], task.arguments

        resumed = @workflow.deserialize(resumed_payload)
        resumed.perform(*resumed_payload.fetch("arguments"))

        assert_equal %w[prepared delivered], @workflow::EVENTS.to_a

        pending = @workflow.deserialize(queued_payload)
        assert_raises(ActiveJob::Continuation::Interrupt) { pending.perform(*queued_payload.fetch("arguments")) }
        pending = @workflow.deserialize(MultiJSON.parse(MultiJSON.generate(pending.serialize)))
        pending.perform(trigger_key)

        assert_equal %w[prepared delivered prepared delivered], @workflow::EVENTS.to_a
      end
    end
  end
end

# frozen_string_literal: true

module R3x
  module Workflow
    class Executor
      def self.build_context(...)
        new(...).build_context
      end

      def initialize(workflow_class:, trigger_key:, trigger_payload: nil, active_job_id: nil)
        @workflow_class = workflow_class
        @trigger_key = trigger_key
        @trigger_payload = trigger_payload
        @active_job_id = active_job_id
      end

      def build_context
        trigger = resolve_trigger

        Context.new(
          trigger: TriggerManager::Execution.new(
            trigger:,
            workflow_key: workflow_class.workflow_key,
            payload: trigger_payload,
          ),
          workflow_key: workflow_class.workflow_key,
          trigger_key: trigger.unique_key,
          active_job_id:,
          workflow_class:,
        )
      end

      private

      attr_reader :workflow_class, :trigger_key, :trigger_payload, :active_job_id

      def resolve_trigger
        return manual_trigger if trigger_key.nil?
        return manual_trigger if manual_trigger.unique_key == trigger_key

        workflow_class.triggers_by_key[trigger_key] || unknown_trigger!
      end

      def manual_trigger
        workflow_class.triggers.find(&:manual?) || Triggers::Manual.new
      end

      def unknown_trigger!
        raise ArgumentError, "Unknown trigger key '#{trigger_key}' for workflow '#{workflow_class.workflow_key}'"
      end
    end
  end
end

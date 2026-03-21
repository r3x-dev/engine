module R3x
  module Workflow
    class Base < ApplicationJob
      include ActiveJob::Continuable
      include Dsl
      include R3x::Concerns::Logger

      class << self
        def method_added(method_name)
          if method_name == :perform && self != Base
            raise ArgumentError, "Do not override #perform in #{name}. Override #run(ctx) instead."
          end
          super
        end
      end

      def perform(trigger_key, trigger_payload: nil)
        R3x::Workflow::PackLoader.load!
        trigger = resolve_trigger(trigger_key)
        ctx = build_context(trigger: trigger, trigger_payload: trigger_payload)
        run(ctx)
      end

      def run(ctx)
        raise NotImplementedError, "#{self.class.name} must implement #run(ctx)"
      end

      private

      def resolve_trigger(trigger_key)
        trigger = self.class.triggers_by_key[trigger_key]
        trigger ||= self.class.triggers.find(&:manual?)

        if trigger.nil?
          raise ArgumentError, "Unknown trigger key '#{trigger_key}' for workflow '#{self.class.workflow_key}'"
        end

        trigger
      end

      def build_context(trigger:, trigger_payload:)
        execution = R3x::TriggerManager::Execution.new(
          trigger: trigger,
          workflow_key: self.class.workflow_key,
          payload: trigger_payload
        )

        Context.new(
          trigger: execution,
          workflow_key: self.class.workflow_key,
          workflow_class: self.class
        )
      end
    end
  end
end

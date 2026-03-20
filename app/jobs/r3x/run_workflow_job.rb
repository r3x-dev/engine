module R3x
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_key, options = nil)
      workflow_key, options = normalize_arguments(workflow_key, options)
      trigger_key = options.fetch(:trigger_key)
      trigger_payload = options[:trigger_payload]

      R3x::WorkflowPackLoader.load!
      workflow_class = R3x::WorkflowRegistry.fetch(workflow_key)
      trigger = find_trigger(workflow_class: workflow_class, trigger_key: trigger_key)

      execution = TriggerExecution.new(
        trigger: trigger,
        workflow_key: workflow_key,
        payload: trigger_payload
      )

      ctx = WorkflowContext.new(
        trigger: execution,
        workflow_key: workflow_key
      )

      workflow_class.new.run(ctx)
    end

    private

    def normalize_arguments(workflow_key, options)
      if workflow_key.is_a?(Hash) && options.nil?
        options = workflow_key
        workflow_key = nil
      end

      options = normalize_options_hash(options)
      workflow_key ||= options[:workflow_key]

      raise ArgumentError, "Missing workflow_key" if workflow_key.blank?

      [ workflow_key, options ]
    end

    def normalize_options_hash(options)
      case options
      when nil
        {}
      when Hash
        options.deep_symbolize_keys
      else
        raise ArgumentError, "Expected options hash, got #{options.class.name}"
      end
    end

    def find_trigger(workflow_class:, trigger_key:)
      trigger = workflow_class.triggers_by_key[trigger_key]

      if trigger.nil?
        raise ArgumentError, "Unknown trigger key '#{trigger_key}' for workflow '#{workflow_class.workflow_key}'"
      end

      trigger
    end
  end
end

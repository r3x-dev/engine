module R3x
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_key, options = nil)
      workflow_key, options = normalize_arguments(workflow_key, options)
      trigger_key = options.fetch(:trigger_key)
      trigger_payload = options[:trigger_payload]

      workflow_class = R3x::Workflow::Registry.fetch(workflow_key)
      workflow_class.perform_now(trigger_key, trigger_payload: trigger_payload)
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
  end
end

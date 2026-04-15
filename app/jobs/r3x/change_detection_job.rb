module R3x
  class ChangeDetectionJob < ApplicationJob
    queue_as :default

    def perform(workflow_key, options = nil)
      workflow_key, options = normalize_arguments(workflow_key, options)
      trigger_key = options.fetch(:trigger_key)
      trigger_state = nil

      with_log_tags(
        "r3x.workflow_key=#{workflow_key}",
        "r3x.trigger_key=#{trigger_key}"
      ) do
        workflow_class = R3x::Workflow::Registry.fetch(workflow_key)
        trigger = find_trigger(workflow_class: workflow_class, trigger_key: trigger_key)
        trigger_state = load_trigger_state(workflow_key: workflow_key, trigger_key: trigger_key, trigger_type: trigger.type)
        result = normalize_result(
          trigger.detect_changes(
            workflow_key: workflow_key,
            state: trigger_state.state.deep_symbolize_keys
          )
        )

        TriggerState.transaction do
          if result[:changed]
            workflow_class.perform_later(trigger_key, trigger_payload: result[:payload])
          end

          trigger_state.record_check!(result)
        end
      end
    rescue => e
      trigger_state.record_error!(e) if defined?(trigger_state) && trigger_state&.persisted?
      raise
    end

    private

    def find_trigger(workflow_class:, trigger_key:)
      trigger = workflow_class.triggers_by_key[trigger_key]

      if trigger.nil?
        raise ArgumentError, "Unknown trigger key '#{trigger_key}' for workflow '#{workflow_class.workflow_key}'"
      end

      unless trigger.change_detecting?
        raise ArgumentError, "Trigger '#{trigger_key}' is not change-detecting"
      end

      trigger
    end

    def load_trigger_state(workflow_key:, trigger_key:, trigger_type:)
      TriggerState.find_or_create_by!(
        workflow_key: workflow_key,
        trigger_key: trigger_key
      ) do |state|
        state.trigger_type = trigger_type.to_s
        state.state = {}
      end
    end

    def normalize_arguments(workflow_key, options)
      if workflow_key.is_a?(Hash) && options.nil?
        options = workflow_key
        workflow_key = nil
      end

      options = normalize_options_hash(options)
      workflow_key ||= options[:workflow_key]

      [ workflow_key.presence || raise(ArgumentError, "Missing workflow_key"), options ]
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

    def normalize_result(result)
      normalized = result.deep_symbolize_keys

      unless normalized.key?(:changed) && normalized.key?(:state)
        raise ArgumentError, "Change-detecting trigger must return a hash with :changed and :state"
      end

      normalized[:state] ||= {}
      normalized[:payload] ||= nil
      normalized
    end
  end
end

module R3x
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_key, options = nil)
      workflow_key, options = normalize_arguments(workflow_key, options)
      trigger_key = options.fetch(:trigger_key)
      trigger_payload = options[:trigger_payload]

      with_log_tags(
        "r3x.workflow_key=#{workflow_key}",
        ("r3x.trigger_key=#{trigger_key}" if trigger_key.present?)
      ) do
        workflow_class = R3x::Workflow::Registry.fetch(workflow_key)
        logger.info "Dispatching workflow class=#{workflow_class.name}"

        workflow_class.perform_now(trigger_key, trigger_payload: trigger_payload)
      rescue => e
        with_log_tags("r3x.job_outcome=failed") do
          logger.error "Workflow dispatch failed error_class=#{e.class} error_message=#{e.message}"
        end

        raise
      end
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

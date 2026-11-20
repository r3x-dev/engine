# frozen_string_literal: true

module R3x
  module Workflow
    module RecurringTaskKey
      extend self

      PREFIX = "workflow"
      PATTERN = "#{PREFIX}:%".freeze

      def build(workflow_key:, trigger_key:)
        "#{PREFIX}:#{workflow_key}:#{trigger_key}"
      end

      def parse(key)
        prefix, workflow_key, trigger_key = key.to_s.split(":", 3)
        unless prefix == PREFIX && workflow_key.present? && trigger_key.present?
          raise ArgumentError, "Unsupported recurring task key: #{key.inspect}"
        end

        { workflow_key:, trigger_key: }
      end
    end
  end
end

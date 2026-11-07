# frozen_string_literal: true

module R3x
  module Workflow
    # Web-only processes do not load workflow packs, so they queue this request.
    # Workers enqueue the real workflow class to apply its callbacks and concurrency
    # limits; a placeholder class with the same name would bypass those settings.
    class EnqueueJob < ApplicationJob
      def perform(class_name, arguments, queue_name:, priority:)
        workflow_class = class_name.constantize
        unless workflow_class < R3x::Workflow::Base
          raise ArgumentError, "Not a workflow class: #{class_name}"
        end

        options = {}
        options[:queue] = queue_name if queue_name.present?
        options[:priority] = priority unless priority.nil?
        positional_arguments = Array(arguments).dup
        keyword_arguments = positional_arguments.last.is_a?(Hash) ? positional_arguments.pop.transform_keys(&:to_sym) : {}

        enqueued_job = if keyword_arguments.empty?
          workflow_class.set(**options).perform_later(*positional_arguments)
        else
          workflow_class.set(**options).perform_later(*positional_arguments, **keyword_arguments)
        end

        unless enqueued_job && enqueued_job.successfully_enqueued? && enqueued_job.provider_job_id.present?
          raise "Workflow enqueue was aborted or discarded for #{class_name}"
        end
      end
    end
  end
end

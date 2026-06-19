# frozen_string_literal: true

module R3x
  module Workflow
    class Execution
      attr_reader :workflow_key, :trigger_key, :active_job_id

      def initialize(workflow_key:, trigger_key: nil, active_job_id: nil)
        @workflow_key = workflow_key
        @trigger_key = trigger_key
        @active_job_id = active_job_id
      end

      def previous_run_at
        return @previous_run_at if defined?(@previous_run_at)

        @previous_run_at = previous_recurring_run_at
      end

      def first_run?
        previous_run_at.nil?
      end

      private

      def previous_recurring_run_at
        return if trigger_key.blank?

        ::Dashboard::RecurringTask
          .find_by_workflow_and_trigger_key(workflow_key:, trigger_key:)
          &.previous_run_at(active_job_id:)
      end
    end
  end
end

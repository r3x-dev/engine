module R3x
  module Workflow
    class Execution
      attr_reader :workflow_key

      def initialize(workflow_key:)
        @workflow_key = workflow_key
      end

      def previous_run_at
        return @previous_run_at if defined?(@previous_run_at)

        @previous_run_at = recurring_task&.last_enqueued_time
      end

      def first_run?
        previous_run_at.nil?
      end

      private

      def recurring_task
        return @recurring_task if defined?(@recurring_task)

        @recurring_task = SolidQueue::RecurringTask.find_by(key: @workflow_key)
      end
    end
  end
end

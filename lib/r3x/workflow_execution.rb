module R3x
  class WorkflowExecution
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

    # Returns SolidQueue::RecurringTask which exposes:
    # - key: workflow_key
    # - schedule: cron expression string
    # - class_name: job class name
    # - arguments: job arguments
    # - queue_name: queue name
    # - last_enqueued_time: last run timestamp
    # - next_time: next scheduled run
    # - previous_time: previous scheduled time (not actual run)
    def recurring_task
      return @recurring_task if defined?(@recurring_task)

      @recurring_task = SolidQueue::RecurringTask.find_by(key: @workflow_key)
    end
  end
end

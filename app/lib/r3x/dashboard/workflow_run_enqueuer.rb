module R3x
  module Dashboard
    class WorkflowRunEnqueuer
      CHANGE_DETECTION_CLASS_NAME = "R3x::ChangeDetectionJob"

      def initialize(workflow_key:, trigger_key:)
        @workflow_key = workflow_key.to_s
        @trigger_key = trigger_key.presence&.to_s
      end

      def enqueue!
        return enqueue_workflow_run_job if trigger_key.blank?

        if recurring_task.class_name == CHANGE_DETECTION_CLASS_NAME
          enqueue_change_detection_job
        else
          enqueue_workflow_run_job
        end
      end

      private
        attr_reader :trigger_key, :workflow_key

        def enqueue_change_detection_job
          R3x::ChangeDetectionJob
            .set(job_options)
            .perform_later(workflow_key, trigger_key: trigger_key)
        end

        def enqueue_workflow_run_job
          if trigger_key.present?
            R3x::RunWorkflowJob
              .set(job_options)
              .perform_later(workflow_key, trigger_key: trigger_key)
          else
            R3x::RunWorkflowJob.perform_later(workflow_key, trigger_key: nil)
          end
        end

        def recurring_task
          @recurring_task ||= SolidQueue::RecurringTask.find_by!(key: task_key)
        end

        def task_key
          return if trigger_key.blank?

          "workflow:#{workflow_key}:#{trigger_key}"
        end

        def job_options
          return {} if trigger_key.blank?

          {
            queue: recurring_task.queue_name,
            priority: recurring_task.priority
          }.compact
        end
    end
  end
end

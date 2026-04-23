module Dashboard
  class RecurringTask < ApplicationRecord
    CHANGE_DETECTION_CLASS_NAME = "R3x::ChangeDetectionJob"

    self.table_name = "solid_queue_recurring_tasks"

    serialize :arguments, coder: SolidQueue::RecurringTask::Arguments, default: []

    scope :workflow_tasks, -> { where("key LIKE ?", "workflow:%").order(:key) }
    scope :for_workflow_key, ->(workflow_key) do
      escaped_workflow_key = ActiveRecord::Base.sanitize_sql_like(workflow_key.to_s, "!")
      workflow_tasks.where("key LIKE ? ESCAPE '!'", "workflow:#{escaped_workflow_key}:%")
    end

    class << self
      def find_by_workflow_and_trigger_key!(workflow_key:, trigger_key:)
        find_by!(key: workflow_task_key(workflow_key, trigger_key))
      end

      def preferred_for_workflow(workflow_key)
        tasks = for_workflow_key(workflow_key).to_a

        tasks.find { |task| task.direct_workflow_class_name.present? } || tasks.first
      end

      def workflow_task_key(workflow_key, trigger_key)
        "workflow:#{workflow_key}:#{trigger_key}"
      end
    end

    def workflow_key
      parsed_key.fetch(:workflow_key)
    end

    def trigger_key
      parsed_key.fetch(:trigger_key)
    end

    def change_detection?
      class_name == CHANGE_DETECTION_CLASS_NAME
    end

    def direct_workflow_class_name
      return if change_detection?

      class_name.presence
    end

    private
      def parsed_key
        @parsed_key ||= begin
          prefix, workflow_key, trigger_key = key.to_s.split(":", 3)
          raise ArgumentError, "Unsupported recurring task key: #{key.inspect}" unless prefix == "workflow" && workflow_key.present? && trigger_key.present?

          { workflow_key: workflow_key, trigger_key: trigger_key }
        end
      end
  end
end

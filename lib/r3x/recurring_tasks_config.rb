module R3x
  class RecurringTasksConfig
    class << self
      def to_h
        result = {}

        WorkflowRegistry.all.each do |workflow_class|
          triggers = workflow_class.schedulable_triggers
          next if triggers.empty?

          workflow_key = workflow_class.workflow_key

          triggers.each do |trigger|
            result_key = "#{workflow_key}:#{trigger.unique_key}"
            result[result_key] = task_definition_for(
              workflow_key: workflow_key,
              trigger: trigger
            )
          end
        end

        result
      end

      private

      def task_definition_for(workflow_key:, trigger:)
        {
          "class" => trigger.change_detecting? ? "R3x::ChangeDetectionJob" : "R3x::RunWorkflowJob",
          "args" => [ workflow_key, { "trigger_key" => trigger.unique_key } ],
          "schedule" => trigger.cron,
          "queue" => "default"
        }
      end
    end
  end
end

module R3x
  class RecurringTasksConfig
    class << self
      def to_h
        result = {}

        WorkflowRegistry.all.each do |workflow_class|
          triggers = workflow_class.triggers.select(&:cron_schedulable?)
          next if triggers.empty?

          workflow_key = workflow_class.workflow_key

          triggers.each do |trigger|
            result[workflow_key] = {
              "class" => "R3x::RunWorkflowJob",
              "args" => [ workflow_key, { "triggered_by" => trigger.type } ],
              "schedule" => trigger.cron,
              "queue" => "default"
            }
          end
        end

        result
      end
    end
  end
end

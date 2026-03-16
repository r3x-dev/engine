module R3x
  class RecurringTasksConfig
    class << self
      def to_h
        result = {}

        WorkflowRegistry.all.each do |workflow_class|
          schedule = workflow_class.schedule_trigger
          next unless schedule

          workflow_key = workflow_class.workflow_key

          result[workflow_key] = {
            "class" => "R3x::RunWorkflowJob",
            "args" => [ workflow_key, { "triggered_by" => "schedule" } ],
            "schedule" => schedule.cron,
            "queue" => "default"
          }
        end

        result
      end
    end
  end
end

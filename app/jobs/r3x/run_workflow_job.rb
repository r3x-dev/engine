module R3x
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_key, trigger_type: "manual")
      R3x::WorkflowPackLoader.load!
      workflow_class = R3x::WorkflowRegistry.fetch(workflow_key)

      trigger = workflow_class.triggers.find { |t| t.type.to_s == trigger_type }
      trigger ||= Triggers::Manual.new

      execution = TriggerExecution.new(
        trigger: trigger,
        workflow_key: workflow_key
      )

      ctx = WorkflowContext.new(
        trigger: execution,
        workflow_key: workflow_key
      )
      workflow_class.new.run(ctx)
    end
  end
end

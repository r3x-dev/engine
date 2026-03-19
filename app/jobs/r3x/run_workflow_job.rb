module R3x
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_key, trigger_key:, trigger_payload: nil)
      R3x::WorkflowPackLoader.load!
      workflow_class = R3x::WorkflowRegistry.fetch(workflow_key)
      trigger = find_trigger(workflow_class: workflow_class, trigger_key: trigger_key)

      execution = TriggerExecution.new(
        trigger: trigger,
        workflow_key: workflow_key,
        payload: trigger_payload
      )

      ctx = WorkflowContext.new(
        trigger: execution,
        workflow_key: workflow_key
      )
      workflow_class.new.run(ctx)
    end

    private

    def find_trigger(workflow_class:, trigger_key:)
      trigger = workflow_class.triggers_by_key[trigger_key]

      if trigger.nil?
        raise ArgumentError, "Unknown trigger key '#{trigger_key}' for workflow '#{workflow_class.workflow_key}'"
      end

      trigger
    end
  end
end

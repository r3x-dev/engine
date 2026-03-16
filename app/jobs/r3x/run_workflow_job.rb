module R3x
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_key, trigger_type: "manual")
      R3x::WorkflowPackLoader.load!
      workflow_class = R3x::WorkflowRegistry.fetch(workflow_key)

      ctx = WorkflowContext.build do |builder|
        builder.trigger_type = trigger_type
        builder.with_solid_queue_task(workflow_key) if trigger_type == "schedule"
      end

      workflow_class.new.run(ctx)
    end
  end
end

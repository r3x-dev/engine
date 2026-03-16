module R3x
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_key, triggered_by: nil)
      R3x::WorkflowPackLoader.load!
      workflow_class = R3x::WorkflowRegistry.fetch(workflow_key)

      ctx = WorkflowContext.build do |builder|
        builder.triggered_by = TriggeredBy.new(triggered_by) if triggered_by
        builder.with_solid_queue_task(workflow_key) if triggered_by == "schedule"
      end

      workflow_class.new.run(ctx)
    end
  end
end

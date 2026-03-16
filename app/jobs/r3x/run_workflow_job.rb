module R3x
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_key, triggered_by: nil)
      R3x::WorkflowPackLoader.load!
      workflow_class = R3x::WorkflowRegistry.fetch(workflow_key)
      triggered_by_obj = triggered_by ? TriggeredBy.new(triggered_by) : nil
      workflow_class.new.run(R3x::WorkflowContext.new(triggered_by: triggered_by_obj))
    end
  end
end

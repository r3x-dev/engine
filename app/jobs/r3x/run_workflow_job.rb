module R3x
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_key)
      R3x::WorkflowPackLoader.load!
      workflow_class = R3x::WorkflowRegistry.fetch(workflow_key)
      workflow_class.new.run(R3x::WorkflowContext.new)
    end
  end
end

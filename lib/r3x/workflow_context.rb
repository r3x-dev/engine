module R3x
  class WorkflowContext
    include R3x::Concerns::Logger

    attr_reader :trigger, :execution

    def initialize(trigger:, workflow_key:)
      @trigger = trigger
      @execution = WorkflowExecution.new(workflow_key: workflow_key)
    end
  end
end

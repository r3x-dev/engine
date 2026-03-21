module R3x
  module Workflow
    class ManualRunner
      def self.run(workflow_key)
        new.run(workflow_key)
      end

      def initialize
        PackLoader.load!
      end

      def run(workflow_key)
        workflow_class = Registry.fetch(workflow_key)
        trigger = workflow_class.triggers.find(&:manual?) || Triggers::Manual.new

        execution = TriggerManager::Execution.new(
          trigger: trigger,
          workflow_key: workflow_key
        )

        ctx = Context.new(
          trigger: execution,
          workflow_key: workflow_key,
          workflow_class: workflow_class
        )

        workflow_class.new.run(ctx)
      end
    end
  end
end

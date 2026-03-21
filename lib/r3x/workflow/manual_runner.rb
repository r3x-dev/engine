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

        workflow_class.new.perform_now(trigger.unique_key)
      end
    end
  end
end

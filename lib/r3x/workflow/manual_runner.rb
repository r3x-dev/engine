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

        workflow_class.perform_now
      end
    end
  end
end

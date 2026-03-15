module Workflows
  class TestWorkflow
    class << self
      def workflow_key
        "test_workflow"
      end

      def trigger_types
        %w[manual schedule]
      end
    end

    def run(ctx)
      {
        "test" => true,
        "message" => "Test workflow executed successfully"
      }
    end
  end
end

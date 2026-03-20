module R3x
  class WorkflowContext
    include R3x::Concerns::Logger

    attr_reader :trigger, :execution, :workflow_class

    def initialize(trigger:, workflow_key:, workflow_class: nil)
      @trigger = trigger
      @workflow_class = workflow_class
      @execution = WorkflowExecution.new(workflow_key: workflow_key)
    end

    def client
      @client ||= ClientProxy.new(workflow_class: workflow_class)
    end

    class ClientProxy
      def initialize(workflow_class:)
        @workflow_class = workflow_class
      end

      def http(verify_ssl: true)
        R3x::Client::Http.new(verify_ssl: verify_ssl)
      end

      def prometheus
        R3x::Client::Prometheus.new
      end

      private

      attr_reader :workflow_class
    end
  end
end

module R3x
  class WorkflowContext
    include R3x::Concerns::Logger

    attr_reader :trigger, :execution

    def initialize(trigger:, workflow_key:)
      @trigger = trigger
      @execution = WorkflowExecution.new(workflow_key: workflow_key)
    end

    def fetch_body(url)
      http_client.get(url)
    end

    def discord_output
      @discord_output ||= R3x::Outputs::Discord.new
    end

    private

    def http_client
      @http_client ||= R3x::Client::Http.new
    end
  end
end

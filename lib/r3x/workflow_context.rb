module R3x
  class WorkflowContext
    def initialize
    end

    def fetch_body(url)
      http_client.get(url)
    end

    def rss_trigger
      @rss_trigger ||= R3x::Triggers::Rss.new
    end

    def discord_output
      @discord_output ||= R3x::Outputs::Discord.new
    end

    def logger
      @logger ||= R3x::Logger.new
    end

    private

    def http_client
      @http_client ||= R3x::Services::HttpClient.new
    end
  end
end

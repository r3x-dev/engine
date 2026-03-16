module R3x
  class WorkflowContext
    include R3x::Concerns::Logger

    attr_reader :triggered_by

    def initialize(triggered_by: nil)
      @triggered_by = triggered_by || TriggeredBy.new(:manual)
    end

    def fetch_body(url)
      http_client.get(url)
    end

    def rss_trigger
      @rss_trigger ||= R3x::Services::RssParser.new
    end

    def discord_output
      @discord_output ||= R3x::Outputs::Discord.new
    end

    private

    def http_client
      @http_client ||= R3x::Services::HttpClient.new
    end
  end
end

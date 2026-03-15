require "faraday"
require "faraday/retry"

module R3x
  module Services
    class DiscordWebhookClient
      def initialize(webhook_url:)
        @webhook_url = webhook_url
        @connection = Faraday.new do |f|
          f.request :json
          f.response :json
        end
      end

      def deliver(content:)
        raise ArgumentError, "Missing Discord webhook URL" if webhook_url.blank?

        connection.post(webhook_url, { content: content })
      end

      private

      attr_reader :webhook_url, :connection
    end
  end
end

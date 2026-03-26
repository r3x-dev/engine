module R3x
  module Outputs
    class Discord
      include R3x::Concerns::Logger

      def initialize
        @webhook_url = ENV["R3X_DISCORD_WEBHOOK_URL"]
      end

      def deliver(content:)
        payload = { "content" => content }

        raise ArgumentError, "Missing Discord webhook URL" if webhook_url.blank?
        R3x::Client::DiscordWebhook.new(webhook_url: webhook_url).deliver(content: content)
      end

      private

      attr_reader :webhook_url
    end
  end
end

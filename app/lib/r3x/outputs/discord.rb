module R3x
  module Outputs
    class Discord
      include R3x::Concerns::Logger

      def initialize
        @mode = ENV.fetch("R3X_DISCORD_MODE", "test")
        @webhook_url = ENV["R3X_DISCORD_WEBHOOK_URL"]
      end

      def deliver(content:)
        payload = { "content" => content }

        case mode
        when "real"
          raise ArgumentError, "Missing Discord webhook URL" if webhook_url.blank?
          R3x::Client::DiscordWebhook.new(webhook_url: webhook_url).deliver(content: content)
        when "test"
          logger.info(content)
        else
          raise ArgumentError, "Unsupported Discord mode: #{mode}. Supported: real, test"
        end

        payload.merge("delivery_mode" => mode)
      end

      private

      attr_reader :mode, :webhook_url
    end
  end
end

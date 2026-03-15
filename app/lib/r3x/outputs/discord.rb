module R3x
  module Outputs
    class Discord
      def initialize
        @mode = ENV.fetch("R3X_DISCORD_MODE", "test")
        @webhook_url = ENV["R3X_DISCORD_WEBHOOK_URL"]
        @logger = R3x::Logger.new
      end

      def deliver(content:)
        payload = { "content" => content }

        case mode
        when "real"
          raise ArgumentError, "Missing Discord webhook URL" if webhook_url.blank?
          R3x::Services::DiscordWebhookClient.new(webhook_url: webhook_url).deliver(content: content)
        when "test"
          logger.info("[DISCORD OUTPUT] #{content}")
        else
          raise ArgumentError, "Unsupported Discord mode: #{mode}. Supported: real, test"
        end

        payload.merge("delivery_mode" => mode)
      end

      private

      attr_reader :logger, :mode, :webhook_url
    end
  end
end

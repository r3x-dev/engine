require "fileutils"

module R3x
  module Outputs
    class Discord
      def initialize
        @mode = ENV.fetch("R3X_DISCORD_MODE", "test")
        @webhook_url = ENV["R3X_DISCORD_WEBHOOK_URL"]
        @capture_path = ENV["R3X_DISCORD_CAPTURE_PATH"]
        @logger = R3x::Logger.new
      end

      def deliver(content:)
        payload = { "content" => content }

        case mode
        when "real"
          raise ArgumentError, "Missing Discord webhook URL" if webhook_url.blank?
          R3x::Services::DiscordWebhookClient.new(webhook_url: webhook_url).deliver(content: content)
        when "test"
          # Test mode - capture to file or log
          if capture_path.present?
            FileUtils.mkdir_p(File.dirname(capture_path))
            File.open(capture_path, "a") { |f| f.puts(MultiJson.dump(payload)) }
          end
          logger.info(content)
        else
          raise ArgumentError, "Unsupported Discord mode: #{mode}. Supported: real, test"
        end

        payload.merge("delivery_mode" => mode)
      end

      private

      attr_reader :capture_path, :logger, :mode, :webhook_url
    end
  end
end

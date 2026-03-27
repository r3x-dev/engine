module R3x
  module Outputs
    class Discord
      include R3x::Concerns::Logger

      def initialize(dry_run: nil)
        @dry_run = R3x::Policy.dry_run_for(:discord, dry_run)
        @webhook_url = ENV["R3X_DISCORD_WEBHOOK_URL"]
      end

      def deliver(content:)
        payload = { "content" => content }

        if dry_run
          logger.info("Discord [DRY-RUN] #{content}")
        else
          raise ArgumentError, "Missing Discord webhook URL" if webhook_url.blank?

          R3x::Client::DiscordWebhook.new(webhook_url: webhook_url).deliver(content: content)
        end

        payload.merge("delivery_mode" => dry_run ? "dry-run" : "real")
      end

      private

      attr_reader :dry_run, :webhook_url
    end
  end
end

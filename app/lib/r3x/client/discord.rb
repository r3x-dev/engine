# frozen_string_literal: true

module R3x
  module Client
    class Discord
      include R3x::Concerns::Logger

      DEFAULT_WEBHOOK_URL_ENV = "DISCORD_WEBHOOK_URL"

      def initialize(webhook_url: nil, webhook_url_env: DEFAULT_WEBHOOK_URL_ENV)
        @webhook_url = webhook_url ||
                       R3x::Env.secure_fetch(webhook_url_env, prefix: "#{DEFAULT_WEBHOOK_URL_ENV}_") ||
                       raise(ArgumentError, "Missing webhook URL")
      end

      def deliver(content:)
        if R3x::Policy.dry_run_for(:discord)
          logger.info "[DRY-RUN] action=deliver content_length=#{content.to_s.bytesize} content_preview=#{content.to_s.first(200).inspect}"

          return { "mode" => "dry_run" }
        end

        HTTPX.post(webhook_url, json: { "content" => content }).raise_for_status

        { "mode" => "real", "content" => content }
      end

      private

      attr_reader :webhook_url
    end
  end
end

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
          logger.info "[DRY-RUN]: content: #{content}"

          return { "mode" => "dry_run" }
        end

        connection.post(webhook_url, json: { "content" => content }).raise_for_status

        { "mode" => "real", "content" => content }
      end

      private

      attr_reader :webhook_url

      def connection
        HTTPX.with({})
      end
    end
  end
end

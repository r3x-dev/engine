# frozen_string_literal: true

module R3x
  module Client
    class Discord
      include R3x::Concerns::Logger

      def initialize(webhook_url: nil, webhook_url_env: nil)
        @webhook_url = webhook_url ||
          R3x::Env.secure_fetch(webhook_url_env, prefix: "DISCORD_WEBHOOK_URL_") ||
          raise(ArgumentError, "Missing webhook URL")
      end

      def deliver(content:)
        if R3x::Policy.dry_run_for(:discord)
          logger.info "[DRY-RUN]: content: #{content}"

          return { "mode" => "dry_run" }
        end

        connection.post(webhook_url, { "content" => content })

        { "mode" => "real", "content" => content }
      end

      private

      attr_reader :webhook_url

      def connection
        Faraday.new do |f|
          f.request :json
          f.response :raise_error
        end
      end
    end
  end
end

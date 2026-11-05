# frozen_string_literal: true

module R3x
  module Client
    class Discord
      include R3x::Concerns::Logger

      DEFAULT_WEBHOOK_URL_ENV = "DISCORD_WEBHOOK_URL"

      def initialize(webhook_url: nil, webhook_url_env: DEFAULT_WEBHOOK_URL_ENV)
        url = webhook_url || R3x::Env.secure_fetch(webhook_url_env, prefix: "#{DEFAULT_WEBHOOK_URL_ENV}_")
        @webhook_url = webhook_url_with_wait(url)
      end

      def deliver(content:)
        if R3x::Policy.dry_run_for(:discord)
          logger.info "[DRY-RUN] action=deliver content_length=#{content.to_s.bytesize} content_preview=#{content.to_s.first(200).inspect}"

          return Delivery.new(status: :dry_run)
        end

        message = HTTPX.post(webhook_url, json: { "content" => content }).raise_for_status.json
        raise ArgumentError, "Discord response must contain a message object" unless message.is_a?(Hash)

        unless message["id"].is_a?(String) && message["id"].present?
          raise ArgumentError, "Discord response must contain a nonblank message id"
        end

        Delivery.new(status: :delivered, message:)
      end

      private

      attr_reader :webhook_url

      # wait=true returns the saved message so we can validate its ID before reporting delivery.
      # With wait=false, Discord can return 204 even when the message was not saved.
      # Replace existing wait values so the configured URL cannot disable this confirmation.
      # https://docs.discord.com/developers/resources/webhook#execute-webhook
      def webhook_url_with_wait(url)
        R3x::GemLoader.require("addressable/uri")
        uri = Addressable::URI.parse(url)
        query = Array.wrap(uri.query_values(Array))
        query.reject! { |key, _| key == "wait" }
        uri.query_values = query << %w[wait true]
        uri.to_s
      end
    end
  end
end

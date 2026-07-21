# frozen_string_literal: true

module R3x
  module Client
    # Client for the Feedway API.
    # See https://github.com/zewelor/feedway
    class Feedway
      DEFAULT_URL_ENV = "FEEDWAY_URL"
      DEFAULT_API_TOKEN_ENV = "FEEDWAY_API_TOKEN"

      def initialize(url_env: DEFAULT_URL_ENV, api_token_env: DEFAULT_API_TOKEN_ENV)
        @base_url = R3x::Env.secure_fetch(url_env, prefix: "#{DEFAULT_URL_ENV}_").delete_suffix("/")
        api_token = R3x::Env.secure_fetch(api_token_env, prefix: "#{DEFAULT_API_TOKEN_ENV}_")
        @connection = HTTPX.with(headers: { "Authorization" => "Bearer #{api_token}" })
      end

      # POST /api/v1/entries
      # Publishes a new entry (or returns deduplicated status for unchanged content).
      # Returns parsed response hash: { "result" => "created"/"deduplicated", "id" => "sha256-v1:..." }
      def publish(content_html:, title: nil)
        raise ArgumentError, "content_html is required" if content_html.blank?

        payload = { content_html: }
        payload[:title] = title if title.present?

        connection.post("#{base_url}/api/v1/entries", json: payload)
                  .raise_for_status
                  .json
      end

      private

      attr_reader :base_url, :connection
    end
  end
end

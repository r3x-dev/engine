# frozen_string_literal: true

module R3x
  module Client
    class Apify
      include R3x::Concerns::Logger

      BASE_URL = "https://api.apify.com/v2"

      def initialize(api_key:)
        @api_key = api_key
      end

      def run_actor(actor_id, input: nil, **options)
        logger.debug { "Apify run_actor #{actor_id}" }

        response = connection.post("#{BASE_URL}/acts/#{actor_id}/runs", json: input, params: options.compact).raise_for_status
        response.json.fetch("data")
      end

      def run_actor_sync_get_items(actor_id, input: nil, format: "json", clean: true, limit: nil, **options)
        logger.debug { "Apify run_actor_sync_get_items #{actor_id}" }

        params = { format: format, clean: clean, limit: limit }.merge(options).compact
        response = connection.post("#{BASE_URL}/acts/#{actor_id}/run-sync-get-dataset-items", json: input, params: params).raise_for_status

        if response.headers["content-type"]&.include?("application/json")
          response.json
        else
          response.body.to_s
        end
      end

      def raw
        connection
      end

      private

      attr_reader :api_key

      def connection
        @connection ||= HTTPX.with(
          timeout: { connect_timeout: 10, operation_timeout: 360 },
          headers: { "Authorization" => "Bearer #{api_key}" }
        )
      end
    end
  end
end

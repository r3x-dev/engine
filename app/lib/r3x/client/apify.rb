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

        response = connection.post("/v2/acts/#{actor_id}/runs", input) do |request|
          request.params = options.compact
        end
        response.body.fetch("data")
      end

      def run_actor_sync_get_items(actor_id, input: nil, format: "json", clean: true, limit: nil, **options)
        logger.debug { "Apify run_actor_sync_get_items #{actor_id}" }

        params = { format: format, clean: clean, limit: limit }.merge(options).compact
        response = connection.post("/v2/acts/#{actor_id}/run-sync-get-dataset-items", input) do |req|
          req.params = params
        end

        response.body
      end

      def raw
        connection
      end

      private

      attr_reader :api_key

      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :json
          f.response :json
          f.response :raise_error
          f.headers["Authorization"] = "Bearer #{api_key}"
          f.options.timeout = 360
          f.options.open_timeout = 10
        end
      end
    end
  end
end

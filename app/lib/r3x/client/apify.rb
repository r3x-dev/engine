# frozen_string_literal: true

module R3x
  module Client
    class Apify
      include R3x::Concerns::Logger

      BASE_URL = "https://api.apify.com/v2"
      TERMINAL_STATUSES = %w[SUCCEEDED FAILED TIMED-OUT ABORTED].to_set.freeze

      def initialize(api_key:)
        @api_key = api_key
      end

      # Run an Actor and return immediately without waiting for completion.
      #
      # @param actor_id [String] Actor ID (e.g. "HDSasDasz78YcAPEB") or
      #   tilde-separated username and name (e.g. "janedoe~my-actor")
      # @param input [Hash, nil] Actor input payload (passed as JSON body)
      # @param timeout [Integer, nil] Timeout in seconds
      # @param memory [Integer, nil] Memory limit in megabytes (power of 2, min 128)
      # @param max_items [Integer, nil] Max dataset items for pay-per-result Actors
      # @param max_total_charge_usd [Float, nil] Max cost for pay-per-event Actors
      # @param restart_on_error [Boolean, nil] Restart on failure
      # @param build [String, nil] Actor build tag or number
      # @param wait_for_finish [Integer, nil] Max seconds to wait for run to finish (max 60)
      # @param webhooks [String, nil] Base64-encoded JSON webhooks array
      # @return [Hash] Run object hash
      def run_actor(actor_id, input: nil, **options)
        logger.debug { "Apify run_actor #{actor_id}" }

        params = options.compact
        response = connection.post("/v2/acts/#{actor_id}/runs", input, params)

        response.body.fetch("data")
      end

      def get_run(run_id, wait_for_finish: nil)
        logger.debug { "Apify get_run #{run_id}" }

        params = { waitForFinish: wait_for_finish }.compact
        response = connection.get("/v2/actor-runs/#{run_id}", params)

        response.body.fetch("data")
      end

      def wait_for_run(run_id, timeout: 300, interval: 10)
        logger.debug { "Apify wait_for_run #{run_id} timeout=#{timeout}" }

        deadline = Time.now + timeout
        loop do
          run = get_run(run_id)
          return run if terminal?(run)
          raise Timeout::Error, "Actor run #{run_id} did not finish within #{timeout}s" if Time.now >= deadline

          sleep(interval)
        end
      end

      # Returns the authenticated Faraday connection for direct API access.
      # Useful for endpoints not yet wrapped with dedicated methods.
      #
      # @return [Faraday::Connection]
      def raw
        connection
      end

      private

      def terminal?(run)
        TERMINAL_STATUSES.include?(run.fetch("status"))
      end

      attr_reader :api_key

      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :json
          f.response :json
          f.response :raise_error
          f.headers["Authorization"] = "Bearer #{api_key}"
          f.options.timeout = 30
          f.options.open_timeout = 10
        end
      end
    end
  end
end

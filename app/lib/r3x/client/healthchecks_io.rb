# frozen_string_literal: true

# Client for the Healthchecks.io Pinging API.
#
# Docs:
# - https://healthchecks.io/docs/
# - https://healthchecks.io/docs/http_api/
#
# Note: the official API docs show URLs like https://hc-ping.com/<uuid>,
# but self-hosted instances default to PING_ENDPOINT = SITE_ROOT + /ping/
# (see https://healthchecks.io/docs/self_hosted_configuration/#PING_ENDPOINT).
# Set HEALTHCHECKS_IO_URL (or pass ping_endpoint:) to the full base including
# /ping/ if your instance requires it, e.g. https://hc.example.com/ping/.
# The check_uuid is then appended automatically.
module R3x
  module Client
    class HealthchecksIO
      include R3x::Concerns::Logger

      def initialize(check_uuid, ping_endpoint: nil, ping_endpoint_env: "HEALTHCHECKS_IO_URL")
        resolved = ping_endpoint || R3x::Env.fetch!(ping_endpoint_env)
        @ping_url = File.join(resolved, check_uuid)
      end

      # Run a block of code with automatic healthcheck lifecycle.
      # Sends a start signal before executing the block, and automatically
      # sends success or failure signal after the block completes.
      #
      # @yield [HealthchecksIO, String] Yields the client and run ID
      # @raise [ArgumentError] If no block is given
      def run
        raise ArgumentError, "Block required" unless block_given?

        rid = SecureRandom.uuid
        send_start(rid: rid)
        begin
          yield(self, rid)
          ping(rid: rid)
        rescue => e
          fail(body: e.message, rid: rid)
          raise
        end
      end

      # Send a success ping to Healthchecks.io.
      # Signals that a job has completed successfully.
      #
      # @param body [String, nil] Optional data to include in the request body
      # @param rid [String, nil] Optional run ID for matching with start signal
      # @return [HealthchecksIO::Response] The response from Healthchecks.io
      def ping(body: nil, rid: nil)
        method = body ? :post : :head
        make_request(method, "", body: body, rid: rid)
      end

      # Send a failure signal to Healthchecks.io.
      # Signals that a job has failed.
      #
      # @param body [String, nil] Optional data to include in the request body
      # @param rid [String, nil] Optional run ID for matching with start signal
      # @return [HealthchecksIO::Response] The response from Healthchecks.io
      def fail(body: nil, rid: nil)
        make_request(:post, "fail", body: body, rid: rid)
      end

      # Send a log signal to Healthchecks.io.
      # Logs information without changing the check status.
      #
      # @param lines [Array<String>, String] Log lines to send
      # @param rid [String, nil] Optional run ID
      # @return [HealthchecksIO::Response] The response from Healthchecks.io
      def log(lines:, rid: nil)
        body = lines.is_a?(Array) ? lines.join("\n") : lines.to_s
        make_request(:post, "log", body: body, rid: rid)
      end

      # Report an exit status to Healthchecks.io.
      # Exit status 0 signals success, all other values signal failure.
      #
      # @param code [Integer] The exit status code (0-255)
      # @param body [String, nil] Optional data to include in the request body
      # @param rid [String, nil] Optional run ID for matching with start signal
      # @return [HealthchecksIO::Response] The response from Healthchecks.io
      def exit_status(code:, body: nil, rid: nil)
        method = body ? :post : :head
        make_request(method, code.to_s, body: body, rid: rid)
      end

      private

      attr_reader :ping_url

      def connection
        @connection ||= HTTPX.with(
          timeout: { connect_timeout: 5, operation_timeout: 10 }
        )
      end

      def send_start(rid: nil)
        make_request(:head, "start", rid: rid)
      end

      def make_request(method, path, body: nil, rid: nil)
        url = path
        url += "?rid=#{rid}" if rid

        logger.debug { "HealthchecksIO #{method.upcase} #{ping_url}/#{url}" }

        target_url = if url.empty?
          ping_url
        elsif url.start_with?("?")
          "#{ping_url}#{url}"
        else
          "#{ping_url}/#{url}"
        end
        response = case method
        when :head
          connection.head(target_url)
        when :post
          connection.post(target_url, body: body)
        else
          raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

        Response.new(response.raise_for_status)
      end
    end
  end
end

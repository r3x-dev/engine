# frozen_string_literal: true

module R3x
  module Client
    class HealthchecksIO
      include R3x::Concerns::Logger

      def initialize(base_url)
        @base_url = base_url.chomp("/")
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
        rescue StandardError => e
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
        make_request(:post, "/fail", body: body, rid: rid)
      end

      # Send a log signal to Healthchecks.io.
      # Logs information without changing the check status.
      #
      # @param lines [Array<String>, String] Log lines to send
      # @param rid [String, nil] Optional run ID
      # @return [HealthchecksIO::Response] The response from Healthchecks.io
      def log(lines:, rid: nil)
        body = lines.is_a?(Array) ? lines.join("\n") : lines.to_s
        make_request(:post, "/log", body: body, rid: rid)
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
        make_request(method, "/#{code}", body: body, rid: rid)
      end

      private

      attr_reader :base_url

      def connection
        @connection ||= Faraday.new(url: base_url) do |f|
          f.response :raise_error
          f.options.timeout = 10
          f.options.open_timeout = 5
        end
      end

      def send_start(rid: nil)
        make_request(:head, "/start", rid: rid)
      end

      def make_request(method, path, body: nil, rid: nil)
        url = build_url(path, rid)

        logger.debug { "HealthchecksIO #{method.upcase} #{url}" }

        response = case method
        when :head
          connection.head(url)
        when :post
          connection.post(url, body)
        else
          raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

        Response.new(response)
      end

      def build_url(path, rid)
        uri = URI.parse(base_url)
        uri.path = uri.path + path
        uri.query = "rid=#{rid}" if rid
        uri.to_s
      end
    end
  end
end

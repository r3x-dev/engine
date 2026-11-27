# frozen_string_literal: true

module R3x
  module Client
    class Discord::Messages
      PAGE_SIZE = 100
      SNOWFLAKE = /\A[1-9][0-9]*\z/
      FALLBACK_RETRY_DELAY = 60
      private_constant :FALLBACK_RETRY_DELAY

      def initialize
        @connection = HTTPX.with(timeout: { total_request_timeout: 10 }, headers: {
          "Authorization" => "Bot #{R3x::Env.fetch!("DISCORD_BOT_TOKEN")}",
          "User-Agent"    => "DiscordBot (https://github.com/r3x-dev/engine, 1.0)",
        })
        @channel_deadlines = {}
        @global_deadline = 0
      end

      def page(channel_id, limit: PAGE_SIZE, after: nil)
        wait_until = [@global_deadline, @channel_deadlines.fetch(channel_id, 0)].max
        if wait_until > monotonic_time
          raise RetryLater, "Discord rate limit reset is pending"
        end

        params = { limit: }
        params[:after] = after if after
        response = connection.get("https://discord.com/api/v10/channels/#{channel_id}/messages", params:).raise_for_status
        if response.headers["x-ratelimit-remaining"] == "0" && (reset_after = response.headers["x-ratelimit-reset-after"])
          @channel_deadlines[channel_id] = deadline(reset_after)
        end
        validate_page(response.json, limit:, after:)
      rescue HTTPX::HTTPError => error
        raise unless [408, 429].include?(error.status) || (500..599).cover?(error.status)

        defer_rate_limited_request(channel_id, error.response) if error.status == 429
        raise RetryLater, "Discord returned HTTP #{error.status}"
      rescue HTTPX::TLSError => error
        raise unless error.message.match?(/unexpected eof while reading|connection reset by peer/i)

        raise RetryLater, error.message
      rescue HTTPX::Connection::HTTP2::GoawayError => error
        raise if error.unrecoverable?

        raise RetryLater, error.message
      rescue IOError, SocketError, HTTPX::TimeoutError, HTTPX::ConnectionError, HTTPX::ResolveError,
        HTTPX::Connection::HTTP2::RstStreamError, HTTPX::Connection::HTTP2::PingError, ::HTTP2::Error::ConnectionClosed, ::HTTP2::Error::ProtocolError,
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPIPE, Errno::ETIMEDOUT,
        Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ENETDOWN, Errno::EHOSTDOWN => error
        raise RetryLater, error.message
      end

      private

      attr_reader :connection

      def validate_page(messages, limit:, after:)
        raise ArgumentError, "Discord response must contain a page of messages" unless messages.is_a?(Array) && messages.size <= limit

        previous = nil
        lower_bound = after.to_i
        messages.each do |message|
          id = message["id"] if message.is_a?(Hash)
          unless id.is_a?(String) && SNOWFLAKE.match?(id) && id.to_i > lower_bound && (!previous || previous > id.to_i)
            raise ArgumentError, "Discord message page contains invalid or out-of-order IDs"
          end
          previous = id.to_i
        end
        messages
      end

      def defer_rate_limited_request(channel_id, response)
        headers = response.headers
        body = rate_limit_body(response)
        scope = rate_limit_scope(headers, body["global"])
        delay = [retry_after_header(headers["retry-after"]), rate_limit_seconds(body["retry_after"])].compact.max
        reset_at = monotonic_time + (delay || FALLBACK_RETRY_DELAY)

        if scope == :channel
          @channel_deadlines[channel_id] = reset_at
        else
          @global_deadline = reset_at
        end

        retry_after = delay ? "#{delay}s" : "#{FALLBACK_RETRY_DELAY}s (fallback for missing or invalid delay)"
        raise RetryLater, "Discord returned HTTP 429 scope=#{scope} retry_after=#{retry_after}"
      end

      def rate_limit_body(response)
        return {} unless response.content_type.mime_type == "application/json"

        body = response.json
        body.is_a?(Hash) ? body : {}
      rescue JSON::ParserError, MultiJSON::ParseError
        {}
      end

      def rate_limit_scope(headers, global)
        scope = headers["x-ratelimit-scope"]
        return :global if global == true || scope == "global" || headers["x-ratelimit-global"] == "true"
        return :channel if global == false || scope == "user" || scope == "shared"

        :unknown
      end

      def retry_after_header(value)
        return unless value

        rate_limit_seconds(value) || [Time.httpdate(value) - Time.current, 0].max
      rescue ArgumentError
        nil
      end

      def deadline(delay)
        seconds = rate_limit_seconds(delay)
        raise ArgumentError, "Invalid Discord rate limit delay" unless seconds

        monotonic_time + seconds
      end

      def rate_limit_seconds(value)
        seconds = Float(value, exception: false)
        seconds if seconds&.finite? && seconds >= 0
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

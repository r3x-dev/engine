# frozen_string_literal: true

module R3x
  module Client
    class Discord::Messages
      PAGE_SIZE = 100
      SNOWFLAKE = /\A[1-9][0-9]*\z/

      def initialize
        @connection = HTTPX.with(headers: {
          "Authorization" => "Bot #{R3x::Env.fetch!("DISCORD_BOT_TOKEN")}",
          "User-Agent"    => "DiscordBot (https://github.com/r3x-dev/engine, 1.0)",
        })
        @channel_deadlines = {}
        @global_deadline = 0
      end

      def page(channel_id, limit: PAGE_SIZE, after: nil)
        wait_until = [@global_deadline, @channel_deadlines.fetch(channel_id, 0)].max
        if wait_until > monotonic_time
          raise RateLimited, "Discord rate limit reset is pending"
        end

        params = { limit: }
        params[:after] = after if after
        response = connection.get("https://discord.com/api/v10/channels/#{channel_id}/messages", params:).raise_for_status
        if response.headers["x-ratelimit-remaining"] == "0" && (reset_after = response.headers["x-ratelimit-reset-after"])
          @channel_deadlines[channel_id] = deadline(reset_after)
        end
        validate_page(response.json, limit:, after:)
      rescue HTTPX::HTTPError => error
        remember_retry_after(channel_id, error.response) if error.status == 429
        raise
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

      def remember_retry_after(channel_id, response)
        headers = response.headers
        delay = headers["retry-after"]
        global = headers["x-ratelimit-global"] == "true" || headers["x-ratelimit-scope"] == "global"
        unless delay
          body = response.json
          delay = body.fetch("retry_after")
          global ||= body.fetch("global")
        end

        if global
          @global_deadline = deadline(delay)
        else
          @channel_deadlines[channel_id] = deadline(delay)
        end
      end

      def deadline(delay)
        seconds = Float(delay)
        raise ArgumentError, "Invalid Discord rate limit delay" unless seconds.finite? && seconds >= 0

        monotonic_time + seconds
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

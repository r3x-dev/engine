# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class Discord::MessagesTest < ActiveSupport::TestCase
      CHANNEL_URL = "https://discord.com/api/v10/channels/42/messages"

      setup do
        R3x::Env.stubs(:fetch!).with("DISCORD_BOT_TOKEN").returns("test-token")
      end

      test "defers the next page until the channel bucket resets" do
        latest = stub_request(:get, "#{CHANNEL_URL}?limit=100")
          .with(headers: { "Authorization" => "Bot test-token" })
          .to_return(json_response([{ id: "102" }], "X-RateLimit-Remaining" => "0", "X-RateLimit-Reset-After" => "120.25"))
        following = stub_request(:get, "#{CHANNEL_URL}?after=102&limit=100").to_return(json_response([]))
        client = Discord::Messages.new

        assert_equal [{ "id" => "102" }], client.page("42", limit: 100)
        assert_raises(Discord::Messages::RetryLater) { client.page("42", limit: 100, after: "102") }
        assert_requested latest
        assert_not_requested following
      end

      test "defers all channels for the duration of a global rate limit" do
        limited = stub_request(:get, "#{CHANNEL_URL}?limit=1").to_return(
          json_response({ retry_after: 120.1, global: true }).merge(status: 429),
        )
        other = stub_request(:get, "https://discord.com/api/v10/channels/43/messages?limit=1").to_return(json_response([]))
        client = Discord::Messages.new

        assert_raises(Discord::Messages::RetryLater) { client.page("42", limit: 1) }
        assert_raises(Discord::Messages::RetryLater) { client.page("43", limit: 1) }
        assert_requested limited, times: 1
        assert_not_requested other
      end

      private

      def json_response(body, headers = {})
        { status: 200, body: MultiJSON.generate(body), headers: { "Content-Type" => "application/json" }.merge(headers) }
      end
    end
  end
end

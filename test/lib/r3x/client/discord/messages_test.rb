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

      test "honors the JSON global limit and full delay even when Retry-After is present" do
        limited = stub_request(:get, "#{CHANNEL_URL}?limit=1").to_return(
          json_response({ retry_after: 120.25, global: true }, "Retry-After" => "120").merge(status: 429),
        )
        other = stub_request(:get, "https://discord.com/api/v10/channels/43/messages?limit=1").to_return(json_response([]))
        client = Discord::Messages.new
        client.stubs(:monotonic_time).returns(100)

        assert_raises(Discord::Messages::RetryLater) { client.page("42", limit: 1) }
        client.stubs(:monotonic_time).returns(220)
        assert_raises(Discord::Messages::RetryLater) { client.page("43", limit: 1) }
        assert_not_requested other
        client.stubs(:monotonic_time).returns(220.25)

        assert_empty client.page("43", limit: 1)
        assert_requested limited, times: 1
      end

      test "uses the JSON delay when the Retry-After header is invalid and only defers the limited channel" do
        limited = stub_request(:get, "#{CHANNEL_URL}?limit=1").to_return(
          json_response({ retry_after: 90, global: false }, "Retry-After" => "bad value").merge(status: 429),
          json_response([]),
        )
        stub_request(:get, "https://discord.com/api/v10/channels/43/messages?limit=1").to_return(json_response([]))
        client = Discord::Messages.new
        client.stubs(:monotonic_time).returns(100)

        assert_raises(Discord::Messages::RetryLater) { client.page("42", limit: 1) }
        assert_empty client.page("43", limit: 1)
        client.stubs(:monotonic_time).returns(189)
        assert_raises(Discord::Messages::RetryLater) { client.page("42", limit: 1) }
        assert_requested limited, times: 1
        client.stubs(:monotonic_time).returns(190)

        assert_empty client.page("42", limit: 1)
      end

      test "honors an HTTP-date on an edge 429 and defers other channels when scope is unknown" do
        now = Time.utc(2026, 11, 24, 12)
        stub_request(:get, "#{CHANNEL_URL}?limit=1").to_return(
          status: 429,
          body: "<html>Too Many Requests</html>",
          headers: { "Content-Type" => "text/html", "Retry-After" => (now + 90).httpdate },
        )
        other = stub_request(:get, "https://discord.com/api/v10/channels/43/messages?limit=1").to_return(json_response([]))
        client = Discord::Messages.new
        client.stubs(:monotonic_time).returns(100)

        travel_to(now) do
          assert_raises(Discord::Messages::RetryLater) { client.page("42", limit: 1) }
        end
        client.stubs(:monotonic_time).returns(189)
        assert_raises(Discord::Messages::RetryLater) { client.page("43", limit: 1) }
        assert_not_requested other
        client.stubs(:monotonic_time).returns(190)

        assert_empty client.page("43", limit: 1)
      end

      test "reports a bounded delay and recovers when the 429 lacks usable retry metadata" do
        stub_request(:get, "#{CHANNEL_URL}?limit=1").to_return(status: 429, body: "{", headers: { "Content-Type" => "application/json" })
        other = stub_request(:get, "https://discord.com/api/v10/channels/43/messages?limit=1").to_return(json_response([]))
        client = Discord::Messages.new
        client.stubs(:monotonic_time).returns(100)

        error = assert_raises(Discord::Messages::RetryLater) { client.page("42", limit: 1) }
        assert_match(/HTTP 429.*scope=unknown.*retry_after=60s.*fallback/, error.message)
        client.stubs(:monotonic_time).returns(159)
        assert_raises(Discord::Messages::RetryLater) { client.page("43", limit: 1) }
        assert_not_requested other
        client.stubs(:monotonic_time).returns(160)

        assert_empty client.page("43", limit: 1)
      end

      private

      def json_response(body, headers = {})
        { status: 200, body: MultiJSON.generate(body), headers: { "Content-Type" => "application/json" }.merge(headers) }
      end
    end
  end
end

require "test_helper"

module R3x
  module Client
    class VictoriaLogsTest < ActiveSupport::TestCase
      setup do
        @original_url = ENV["R3X_VICTORIA_LOGS_URL"]
      end

      teardown do
        ENV["R3X_VICTORIA_LOGS_URL"] = @original_url
        WebMock.reset!
      end

      test "raises when R3X_VICTORIA_LOGS_URL is missing" do
        ENV.delete("R3X_VICTORIA_LOGS_URL")

        error = assert_raises(ArgumentError) do
          VictoriaLogs.new
        end

        assert_equal "Missing R3X_VICTORIA_LOGS_URL", error.message
      end

      test "queries and parses json lines" do
        ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

        stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
          .with(body: hash_including("query" => "_time:5m error", "limit" => "2"))
          .to_return(
            status: 200,
            body: [
              { "_time" => "2026-04-15T12:00:00Z", "_msg" => "first" }.to_json,
              { "_time" => "2026-04-15T12:00:01Z", "_msg" => "second" }.to_json
            ].join("\n")
          )

        result = VictoriaLogs.new.query(query: "_time:5m error", limit: 2)

        assert_equal 2, result.size
        assert_equal "first", result.first["_msg"]
        assert_equal "second", result.second["_msg"]
      end
    end
  end
end

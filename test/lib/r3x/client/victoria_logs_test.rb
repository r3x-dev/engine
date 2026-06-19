# frozen_string_literal: true

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

      test "supports custom url_env with matching prefix" do
        ENV["R3X_VICTORIA_LOGS_URL_CUSTOM"] = "http://custom-victoria-logs.test:9428"

        stub_request(:post, "http://custom-victoria-logs.test:9428/select/logsql/query")
          .with(body: hash_including("query" => "_msg:test | sort by (_time)"))
          .to_return(status: 200, body: "")

        result = VictoriaLogs.new(url_env: "R3X_VICTORIA_LOGS_URL_CUSTOM").query(query: "_msg:test")

        assert_equal [], result
      ensure
        ENV.delete("R3X_VICTORIA_LOGS_URL_CUSTOM")
      end

      test "rejects url_env outside victoria logs prefix" do
        ENV["VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

        error = assert_raises(ArgumentError) do
          VictoriaLogs.new(url_env: "VICTORIA_LOGS_URL")
        end

        assert_equal "Key 'VICTORIA_LOGS_URL' must be 'R3X_VICTORIA_LOGS_URL' or start with 'R3X_VICTORIA_LOGS_URL_'", error.message
      ensure
        ENV.delete("VICTORIA_LOGS_URL")
      end

      test "queries and parses json lines" do
        ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

        stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
          .with(body: hash_including("query" => "_time:5m error | sort by (_time)", "limit" => "2"))
          .to_return(
            status: 200,
            body: [
              { "_time" => "2026-04-15T12:00:00Z", "_msg" => "first" }.to_json,
              { "_time" => "2026-04-15T12:00:01Z", "_msg" => "second" }.to_json,
            ].join("\n"),
          )

        result = VictoriaLogs.new.query(query: "_time:5m error", limit: 2)

        assert_equal 2, result.size
        assert_equal "first", result.first["_msg"]
        assert_equal "second", result.second["_msg"]
        assert_requested :post, "http://victoria-logs.test:9428/select/logsql/query",
          body: hash_including("query" => "_time:5m error | sort by (_time)")
      end

      test "keeps caller-provided sort pipe" do
        ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

        stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
          .with(body: hash_including("query" => "_time:5m error | sort by (_time desc)"))
          .to_return(status: 200, body: "")

        VictoriaLogs.new.query(query: "_time:5m error | sort by (_time desc)", limit: 2)

        assert_requested :post, "http://victoria-logs.test:9428/select/logsql/query"
      end

      test "preserves sub-second precision for start and end timestamps" do
        ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

        start_at = Time.zone.parse("2026-04-17T14:02:10.658368Z")
        end_at = Time.zone.parse("2026-04-17T14:09:42.734160Z")

        stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
          .with(body: hash_including(
            "start" => "2026-04-17T14:02:10.658368Z",
            "end"   => "2026-04-17T14:09:42.734160Z",
          ))
          .to_return(status: 200, body: "")

        VictoriaLogs.new.query(query: "_msg:test", start_at:, end_at:)

        assert_requested :post, "http://victoria-logs.test:9428/select/logsql/query"
      end
    end
  end
end

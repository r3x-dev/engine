require "test_helper"

module R3x
  module Dashboard
    class ApplicationHelperTest < ActionView::TestCase
      test "dashboard relative time describes future timestamps as upcoming" do
        assert_match "from now", dashboard_relative_time(5.minutes.from_now)
      end

      test "dashboard relative time describes past timestamps as elapsed" do
        assert_match "ago", dashboard_relative_time(5.minutes.ago)
      end

      test "dashboard log time renders clock time instead of relative time" do
        assert_includes dashboard_log_time(Time.zone.parse("2026-04-15T12:00:01Z")), "12:00:01"
      end

      test "dashboard absolute timestamp renders date and time instead of relative time" do
        rendered = dashboard_absolute_timestamp(Time.zone.parse("2026-04-15T12:00:01Z"))

        assert_includes rendered, "2026-04-15 12:00:01"
        refute_includes rendered, ">about"
      end

      test "dashboard absolute timestamp respects R3X_TIMEZONE" do
        original_timezone = ENV["R3X_TIMEZONE"]
        ENV["R3X_TIMEZONE"] = "America/New_York"

        rendered = dashboard_absolute_timestamp(Time.zone.parse("2026-04-15T12:00:01Z"))

        assert_includes rendered, "2026-04-15 08:00:01 EDT"
      ensure
        ENV["R3X_TIMEZONE"] = original_timezone
      end

      test "dashboard log state empty message prefers waiting copy for refreshable panels" do
        assert_equal "Waiting for first log line...", dashboard_log_state_empty_message(refreshable: true, empty_message: "No indexed logs were found.")
        assert_equal "No indexed logs were found.", dashboard_log_state_empty_message(refreshable: false, empty_message: "No indexed logs were found.")
      end

      test "dashboard log level helpers map labels and tones" do
        assert_equal "WARN", dashboard_log_level_label("warn")
        assert_equal "warn", dashboard_log_level_tone("warn")
        assert_equal "danger", dashboard_log_level_tone("fatal")
        assert_equal "muted", dashboard_log_level_tone("unknown")
      end

      test "dashboard error details stay visible for truncated single-line messages" do
        long_error = "API error: " + ("x" * 220)

        assert dashboard_error_details_visible?(long_error)
        refute dashboard_error_multiline?(long_error)
      end

      test "dashboard structured error parses ruby hash dumps into exception message and backtrace" do
        error = dashboard_structured_error(
          '{"exception_class" => "HTTPX::HTTPError", "message" => "the server responded with status 403", "backtrace" => ["line one", "line two"]}'
        )

        assert_equal "HTTPX::HTTPError", error[:exception_class]
        assert_equal "the server responded with status 403", error[:message]
        assert_equal [ "line one", "line two" ], error[:backtrace]
      end

      test "dashboard duration renders hh:mm:ss" do
        start_time = Time.zone.parse("2026-04-23 10:00:00 UTC")
        end_time = Time.zone.parse("2026-04-23 11:02:03 UTC")

        assert_equal "01:02:03", dashboard_duration(start_time, end_time)
      end
    end
  end
end

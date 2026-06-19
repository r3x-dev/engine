# frozen_string_literal: true

require "test_helper"

module R3x
  module Dashboard
    class ApplicationHelperTest < ActionView::TestCase
      test "dashboard timestamp renders absolute time without relative copy" do
        rendered = dashboard_timestamp(Time.zone.parse("2026-04-15T12:00:01Z"))

        assert_includes rendered, "15.04.2026 12:00:01"
        assert_not_includes rendered, "ago"
        assert_not_includes rendered, "from now"
      end

      test "dashboard timestamp respects R3X_TIMEZONE" do
        original_timezone = ENV["R3X_TIMEZONE"]
        ENV["R3X_TIMEZONE"] = "America/New_York"

        rendered = dashboard_timestamp(Time.zone.parse("2026-04-15T12:00:01Z"))

        assert_includes rendered, "15.04.2026 08:00:01 EDT"
      ensure
        ENV["R3X_TIMEZONE"] = original_timezone
      end

      test "dashboard log time renders clock time instead of relative time" do
        assert_includes dashboard_log_time(Time.zone.parse("2026-04-15T12:00:01Z")), "12:00:01"
      end


      test "dashboard trigger details shows schedule details without hash as visible text" do
        rendered = dashboard_trigger_details(
          cron: "0 12 * * * Europe/Warsaw",
          mode: "scheduled",
          unique_key: "schedule:abc123",
        )

        assert_includes rendered, "schedule:&quot;0 12 * * * Europe/Warsaw&quot;"
        assert_includes rendered, "schedule:abc123"
        assert_not_includes rendered, ">schedule:abc123<"
      end

      test "dashboard trigger details formats one-part trigger keys" do
        rendered = dashboard_trigger_details(unique_key: "feed:abc123", mode: "observed")

        assert_includes rendered, ">abc123<"
        assert_includes rendered, "feed:abc123"
      end

      test "dashboard trigger key label hides trigger type prefix" do
        assert_equal "inventory", dashboard_trigger_key_label("schedule:inventory")
        assert_equal "abc123", dashboard_trigger_key_label("feed:abc123")
        assert_equal "manual/default", dashboard_trigger_key_label(nil)
      end

      test "dashboard run trigger label prefers schedule from persisted recurring task" do
        assert_equal(
          'schedule:"15 * * * *"',
          dashboard_run_trigger_label(trigger_key: "schedule:inventory", trigger_schedule: "15 * * * *"),
        )
        assert_equal "inventory", dashboard_run_trigger_label(trigger_key: "schedule:inventory")
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
        assert_not dashboard_error_multiline?(long_error)
      end

      test "dashboard structured error parses ruby hash dumps into exception message and backtrace" do
        error = dashboard_structured_error(
          '{"exception_class" => "HTTPX::HTTPError", "message" => "the server responded with status 403", "backtrace" => ["line one", "line two"]}',
        )

        assert_equal "HTTPX::HTTPError", error[:exception_class]
        assert_equal "the server responded with status 403", error[:message]
        assert_equal ["line one", "line two"], error[:backtrace]
      end

      test "dashboard duration renders hh:mm:ss" do
        start_time = Time.zone.parse("2026-04-23 10:00:00 UTC")
        end_time = Time.zone.parse("2026-04-23 11:02:03 UTC")

        assert_equal "01:02:03", dashboard_duration(start_time, end_time)
      end
    end
  end
end

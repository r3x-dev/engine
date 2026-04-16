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
    end
  end
end

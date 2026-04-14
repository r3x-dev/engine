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
    end
  end
end

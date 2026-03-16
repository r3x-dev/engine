require "test_helper"

module R3x
  class TriggeredByTest < ActiveSupport::TestCase
    test "schedule? returns true for schedule type" do
      tb = TriggeredBy.new(:schedule)
      assert tb.schedule?
      refute tb.rss?
      refute tb.manual?
    end

    test "rss? returns true for rss type" do
      tb = TriggeredBy.new(:rss)
      refute tb.schedule?
      assert tb.rss?
      refute tb.manual?
    end

    test "manual? returns true for manual type" do
      tb = TriggeredBy.new(:manual)
      refute tb.schedule?
      refute tb.rss?
      assert tb.manual?
    end

    test "type returns symbol" do
      tb = TriggeredBy.new("schedule")
      assert_equal :schedule, tb.type
    end

    test "equality with symbol" do
      tb = TriggeredBy.new(:schedule)
      assert tb == :schedule
      refute tb == :rss
    end

    test "equality with another TriggeredBy" do
      tb1 = TriggeredBy.new(:schedule)
      tb2 = TriggeredBy.new(:schedule)
      tb3 = TriggeredBy.new(:rss)
      assert tb1 == tb2
      refute tb1 == tb3
    end

    test "inequality with other types" do
      tb = TriggeredBy.new(:schedule)
      refute tb == "schedule"
      refute tb.nil?
      refute tb == 123
    end
  end
end

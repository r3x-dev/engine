require "test_helper"

module R3x
  class TriggeredByTest < ActiveSupport::TestCase
    test "schedule? returns true for schedule type" do
      tb = TriggeredBy.new(:schedule)
      assert tb.schedule?
      refute tb.manual?
    end

    test "manual? returns true for manual type" do
      tb = TriggeredBy.new(:manual)
      refute tb.schedule?
      assert tb.manual?
    end

    test "type returns symbol" do
      tb = TriggeredBy.new("schedule")
      assert_equal :schedule, tb.type
    end

    test "equality with symbol" do
      tb = TriggeredBy.new(:schedule)
      assert tb == :schedule
    end

    test "equality with another TriggeredBy" do
      tb1 = TriggeredBy.new(:schedule)
      tb2 = TriggeredBy.new(:schedule)
      assert tb1 == tb2
    end

    test "inequality with other types" do
      tb = TriggeredBy.new(:schedule)
      refute tb == "schedule"
      refute tb.nil?
      refute tb == 123
    end
  end
end

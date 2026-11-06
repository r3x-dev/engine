# frozen_string_literal: true

require "test_helper"

module R3x
  module Triggers
    class KeyTest < ActiveSupport::TestCase
      test "named key is independent of cron and timezone" do
        first = Schedule.new(key: :daily, cron: "0 8 * * *", timezone: "UTC")
        changed = Schedule.new(key: "daily", cron: "0 9 * * *", timezone: "Europe/Warsaw")

        assert_equal "schedule:daily", first.unique_key
        assert_equal first.unique_key, changed.unique_key
        assert_equal "daily", first.key
        assert_not_includes first.options, :key
      end

      test "unnamed triggers preserve their existing hash key" do
        schedule = Schedule.new(cron: "0 8 * * *")

        assert_equal "schedule:cd8b2299f7bb5e3e", schedule.unique_key
        assert_nil schedule.key
      end

      test "manual triggers also support a named key" do
        assert_equal "manual:refresh", Manual.new(key: :refresh).unique_key
      end

      test "invalid explicit keys raise collected DSL configuration errors" do
        ["", " ", "Daily", "daily:one", "../daily", "daily job", 1, false, []].each do |key|
          workflow = Class.new(R3x::Workflow::Base)

          error = assert_raises(ConfigurationError) do
            workflow.trigger(:schedule, key:, cron: "0 8 * * *")
          end

          assert_includes error.message, "Key must be a lowercase name starting with a letter"
        end
      end

      test "duplicate named keys are rejected even with different schedules" do
        workflow = Class.new(R3x::Workflow::Base)
        workflow.trigger(:schedule, key: :daily, cron: "0 8 * * *")

        error = assert_raises(ArgumentError) do
          workflow.trigger(:schedule, key: :daily, cron: "0 9 * * *")
        end

        assert_equal "Trigger with key 'schedule:daily' already exists", error.message
      end
    end
  end
end

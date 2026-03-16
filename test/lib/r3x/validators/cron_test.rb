require "test_helper"

module R3x
  module Validators
    class CronTest < ActiveSupport::TestCase
      test "accepts standard cron expression" do
        assert_nothing_raised do
          Cron.validate!("0 13 * * *")
        end
      end

      test "accepts human readable cron via fugit" do
        assert_nothing_raised do
          Cron.validate!("every day at 13:00")
        end
      end

      test "accepts various human readable formats" do
        assert_nothing_raised do
          Cron.validate!("every hour")
          Cron.validate!("every 15 minutes")
          Cron.validate!("every weekday at 9am")
        end
      end

      test "rejects invalid cron" do
        assert_raises(ArgumentError) do
          Cron.validate!("invalid cron")
        end
      end

      test "rejects empty cron" do
        assert_nothing_raised do
          Cron.validate!("")
        end
      end

      test "rejects nil cron" do
        assert_nothing_raised do
          Cron.validate!(nil)
        end
      end

      test "uses custom field name in error message" do
        error = assert_raises(ArgumentError) do
          Cron.validate!("not valid", field_name: "every")
        end
        assert_match(/every:/, error.message)
      end
    end
  end
end

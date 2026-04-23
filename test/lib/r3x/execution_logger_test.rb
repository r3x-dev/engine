require "test_helper"

module R3x
  class ExecutionLoggerTest < ActiveSupport::TestCase
    test "falls back to rails logger outside execution scope" do
      assert_same Rails.logger, ExecutionLogger.current
    end

    test "restores the previous execution logger after nested scopes" do
      outer_logger = build_test_logger(StringIO.new)
      inner_logger = build_test_logger(StringIO.new)

      ExecutionLogger.with(outer_logger) do
        assert_same outer_logger, ExecutionLogger.current

        ExecutionLogger.with(inner_logger) do
          assert_same inner_logger, ExecutionLogger.current
        end

        assert_same outer_logger, ExecutionLogger.current
      end

      assert_same Rails.logger, ExecutionLogger.current
    end
  end
end

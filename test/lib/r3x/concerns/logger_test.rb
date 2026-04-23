require "test_helper"

module R3x
  module Concerns
    class LoggerTest < ActiveSupport::TestCase
      class TestHelper
        include R3x::Concerns::Logger

        def call
          logger.info("hello from instance")
        end
      end

      test "extended logger uses receiver name tag" do
        klass = Class.new do
          extend R3x::Concerns::Logger

          def self.name
            "R3x::TestLogger"
          end
        end

        output = capture_logged_output do
          klass.logger.info("hello")
        end

        assert_includes output, "R3x::TestLogger"
        refute_includes output, "[Class]"
      end

      test "instance logger prefers execution logger when present" do
        io = StringIO.new
        execution_logger = build_test_logger(io)

        R3x::ExecutionLogger.with(execution_logger) do
          TestHelper.new.call
        end

        assert_includes io.string, "R3x::Concerns::LoggerTest::TestHelper"
        assert_includes io.string, "hello from instance"
      end
    end
  end
end

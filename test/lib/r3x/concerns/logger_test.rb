require "test_helper"

module R3x
  module Concerns
    class LoggerTest < ActiveSupport::TestCase
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
    end
  end
end

require "test_helper"

module R3x
  class LogFormatterTest < ActiveSupport::TestCase
    test "formats tagged logs as json" do
      io = StringIO.new
      logger = ActiveSupport::TaggedLogging.new(
        ActiveSupport::Logger.new(io).tap do |base_logger|
          base_logger.formatter = LogFormatter.new
        end
      )

      logger.tagged("MyClass", "r3x.run_active_job_id=123") do
        logger.warn("tagged warn")
      end

      payload = MultiJson.load(io.string)

      assert_equal "warn", payload.fetch("level")
      assert_equal "tagged warn", payload.fetch("message")
      assert_equal [ "MyClass", "r3x.run_active_job_id=123" ], payload.fetch("tags")
      assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/, payload.fetch("time"))
    end

    test "formats plain logs as json without tags" do
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io).tap do |base_logger|
        base_logger.formatter = LogFormatter.new
      end

      logger.info("plain message")

      payload = MultiJson.load(io.string)

      assert_equal "info", payload.fetch("level")
      assert_equal "plain message", payload.fetch("message")
      refute payload.key?("tags")
    end
  end
end

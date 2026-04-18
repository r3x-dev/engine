require "test_helper"

module R3x
  class LogFormatterTest < ActiveSupport::TestCase
    test "formats tagged logs as json when mode is json" do
      io = StringIO.new
      logger = ActiveSupport::TaggedLogging.new(
        ActiveSupport::Logger.new(io).tap do |base_logger|
          base_logger.formatter = LogFormatter.new(mode: :json)
        end
      )

      logger.tagged("MyClass", "r3x.run_active_job_id=123") do
        logger.warn("tagged warn")
      end

      payload = MultiJson.load(io.string)

      assert_equal "warn", payload.fetch("level")
      assert_equal "tagged warn", payload.fetch("message")
      assert_equal [ "MyClass", "r3x.run_active_job_id=123" ], payload.fetch("tags")
    end

    test "formats tagged logs as flat text when mode is text" do
      io = StringIO.new
      logger = ActiveSupport::TaggedLogging.new(
        ActiveSupport::Logger.new(io).tap do |base_logger|
          base_logger.formatter = LogFormatter.new(mode: :text)
        end
      )

      logger.tagged("MyClass", "r3x.run_active_job_id=123") do
        logger.info("line one\nline two")
      end

      output = io.string

      assert_includes output, "INFO"
      assert_includes output, "[MyClass]"
      assert_includes output, "[r3x.run_active_job_id=123]"
      assert_includes output, "line one line two"
      refute_match(/\A\s*\{/, output)
    end
  end
end

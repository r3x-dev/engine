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

    test "preserves bracketed literal prefixes in plain messages" do
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io).tap do |base_logger|
        base_logger.formatter = LogFormatter.new
      end

      logger.info("[DRY-RUN]: email not sent")

      payload = MultiJson.load(io.string)

      assert_equal "[DRY-RUN]: email not sent", payload.fetch("message")
      refute payload.key?("tags")
    end

    test "merges hash payload as top-level fields" do
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io).tap do |base_logger|
        base_logger.formatter = LogFormatter.new
      end

      logger.error(
        message: "Workflow run failed",
        error_class: "NameError",
        error_message: "uninitialized constant",
        backtrace: [ "app/lib/a.rb:1", "app/lib/b.rb:2" ]
      )

      payload = MultiJson.load(io.string)

      assert_equal "error", payload.fetch("level")
      assert_equal "Workflow run failed", payload.fetch("message")
      assert_equal "NameError", payload.fetch("error_class")
      assert_equal "uninitialized constant", payload.fetch("error_message")
      assert_equal [ "app/lib/a.rb:1", "app/lib/b.rb:2" ], payload.fetch("backtrace")
      assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/, payload.fetch("time"))
    end

    test "raises on unsupported message type" do
      formatter = LogFormatter.new

      error = assert_raises(ArgumentError) do
        formatter.call("error", Time.current, nil, 12345)
      end

      assert_equal "Unsupported log message type: Integer", error.message
    end
  end
end

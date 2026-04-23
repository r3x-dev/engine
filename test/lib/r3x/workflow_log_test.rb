require "test_helper"

module R3x
  class WorkflowLogTest < ActiveSupport::TestCase
    setup do
      @log_files = [].freeze
      @original_rotation_count = ENV["R3X_WORKFLOW_LOG_ROTATION_COUNT"]
      @original_rotation_size_bytes = ENV["R3X_WORKFLOW_LOG_ROTATION_SIZE_BYTES"]
    end

    teardown do
      ENV["R3X_WORKFLOW_LOG_ROTATION_COUNT"] = @original_rotation_count
      ENV["R3X_WORKFLOW_LOG_ROTATION_SIZE_BYTES"] = @original_rotation_size_bytes
      @log_files.each(&:close!)
    end

    test "build_logger mirrors readable stdout and structured jsonl file output" do
      stdout = StringIO.new
      path = build_log_path
      logger = WorkflowLog.build_logger(stdout: stdout, path: path)

      logger.tagged("TestWorkflow", "r3x.run_active_job_id=aj-123") do
        logger.warn("hello from workflow logger")
      end
      logger.flush

      assert_respond_to logger, :info
      assert_respond_to logger, :level=
      assert_equal [], logger.formatter.current_tags
      assert_includes stdout.string, "[TestWorkflow]"
      assert_includes stdout.string, "hello from workflow logger"

      payload = MultiJson.load(File.readlines(path).last)

      assert_equal "warn", payload.fetch("level")
      assert_equal "hello from workflow logger", payload.fetch("message")
      assert_equal [ "TestWorkflow", "r3x.run_active_job_id=aj-123" ], payload.fetch("tags")
      assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/, payload.fetch("time"))
    end

    test "tagged without a block preserves current_tags compatibility" do
      logger = WorkflowLog.build_logger(stdout: StringIO.new, path: build_log_path)
      tagged_logger = logger.tagged("ActiveJob", "aj-123")

      assert_equal [ "ActiveJob", "aj-123" ], tagged_logger.formatter.current_tags
    end

    test "uses structured stdout logging in production" do
      stdout = StringIO.new
      logger = WorkflowLog.build_logger(stdout: stdout, path: build_log_path, env: "production")

      logger.info("hello from production workflow logger")
      logger.flush

      payload = MultiJson.load(stdout.string)

      assert_equal "info", payload.fetch("level")
      assert_equal "hello from production workflow logger", payload.fetch("message")
    end

    test "honors app log level for stdout and jsonl sinks" do
      stdout = StringIO.new
      path = build_log_path
      original_log_level = Rails.application.config.log_level
      Rails.application.config.log_level = :info
      logger = WorkflowLog.build_logger(stdout: stdout, path: path)

      logger.debug("debug line should be filtered")
      logger.info("info line should be kept")
      logger.flush

      refute_includes stdout.string, "debug line should be filtered"
      assert_includes stdout.string, "info line should be kept"

      payloads = File.readlines(path).map { |line| MultiJson.load(line) }

      assert_equal [ "info" ], payloads.map { |payload| payload.fetch("level") }
      assert_equal [ "info line should be kept" ], payloads.map { |payload| payload.fetch("message") }
    ensure
      Rails.application.config.log_level = original_log_level
    end

    test "rotates the workflow log file by size" do
      ENV["R3X_WORKFLOW_LOG_ROTATION_COUNT"] = "1"
      ENV["R3X_WORKFLOW_LOG_ROTATION_SIZE_BYTES"] = "200"
      path = build_log_path
      logger = WorkflowLog.build_logger(stdout: StringIO.new, path: path)

      20.times do
        logger.info("x" * 80)
      end
      logger.close

      assert File.exist?("#{path}.0")
    end

    private
      def build_log_path
        file = Tempfile.new([ "workflow-log", ".jsonl" ])
        file.close
        @log_files = (@log_files + [ file ]).freeze
        file.path
      end
  end
end

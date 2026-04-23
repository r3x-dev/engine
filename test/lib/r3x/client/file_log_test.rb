require "test_helper"

module R3x
  module Client
    class FileLogTest < ActiveSupport::TestCase
      setup do
        @log_files = [].freeze
        @original_workflow_path = ENV["R3X_WORKFLOW_LOG_PATH"]
      end

      teardown do
        ENV["R3X_WORKFLOW_LOG_PATH"] = @original_workflow_path
        @log_files.each(&:close!)
      end

      test "queries matching file log lines inside the requested window" do
        path = write_log_file(
          "{\"level\":\"info\",\"message\":\"keep me\",\"time\":\"2026-04-15T12:00:01.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}",
          "{\"level\":\"warn\",\"message\":\"other run\",\"time\":\"2026-04-15T12:00:02.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-999\"]}",
          "not json",
          "{\"level\":\"error\",\"message\":\"too late\",\"time\":\"2026-04-15T12:01:00.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}"
        )

        result = FileLog.new(path: path).query(
          query: '_msg:"r3x.run_active_job_id=aj-123" | fields _time, _msg',
          start_at: Time.zone.parse("2026-04-15T12:00:00Z"),
          end_at: Time.zone.parse("2026-04-15T12:00:30Z"),
          limit: 10
        )

        assert_equal 1, result.size
        assert_equal "2026-04-15T12:00:01.000000Z", result.first.fetch("_time")
        assert_includes result.first.fetch("_msg"), "\"message\":\"keep me\""
      end

      test "returns the latest matching entries first when applying the limit" do
        path = write_log_file(
          "{\"level\":\"info\",\"message\":\"first\",\"time\":\"2026-04-15T12:00:01.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}",
          "{\"level\":\"info\",\"message\":\"second\",\"time\":\"2026-04-15T12:00:02.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}",
          "{\"level\":\"info\",\"message\":\"third\",\"time\":\"2026-04-15T12:00:03.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}"
        )

        result = FileLog.new(path: path).query(
          query: '_msg:"r3x.run_active_job_id=aj-123"',
          start_at: Time.zone.parse("2026-04-15T12:00:00Z"),
          end_at: Time.zone.parse("2026-04-15T12:01:00Z"),
          limit: 2
        )

        assert_equal 2, result.size
        assert_includes result.first.fetch("_msg"), "\"message\":\"second\""
        assert_includes result.second.fetch("_msg"), "\"message\":\"third\""
      end

      test "reads rotated workflow log archives in chronological order before applying the limit" do
        path = write_log_file(
          "{\"level\":\"info\",\"message\":\"active\",\"time\":\"2026-04-15T12:00:04.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}"
        )
        File.write(
          "#{path}.0",
          "{\"level\":\"info\",\"message\":\"archive newer\",\"time\":\"2026-04-15T12:00:03.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}\n"
        )
        File.write(
          "#{path}.2",
          "{\"level\":\"info\",\"message\":\"archive oldest\",\"time\":\"2026-04-15T12:00:01.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}\n"
        )
        File.write(
          "#{path}.1",
          "{\"level\":\"info\",\"message\":\"archive middle\",\"time\":\"2026-04-15T12:00:02.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}\n"
        )

        result = FileLog.new(path: path).query(
          query: '_msg:"r3x.run_active_job_id=aj-123"',
          start_at: Time.zone.parse("2026-04-15T12:00:00Z"),
          end_at: Time.zone.parse("2026-04-15T12:01:00Z"),
          limit: 3
        )

        assert_equal 3, result.size
        assert_includes result.first.fetch("_msg"), "\"message\":\"archive middle\""
        assert_includes result.second.fetch("_msg"), "\"message\":\"archive newer\""
        assert_includes result.third.fetch("_msg"), "\"message\":\"active\""
      end

      test "reads rotated archives even when the active log file is missing" do
        path = Tempfile.new([ "file-log-missing-active", ".log" ]).path
        File.delete(path)
        File.write(
          "#{path}.0",
          "{\"level\":\"info\",\"message\":\"archive only\",\"time\":\"2026-04-15T12:00:01.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}\n"
        )

        result = FileLog.new(path: path).query(
          query: '_msg:"r3x.run_active_job_id=aj-123"',
          start_at: Time.zone.parse("2026-04-15T12:00:00Z"),
          end_at: Time.zone.parse("2026-04-15T12:01:00Z"),
          limit: 10
        )

        assert_equal 1, result.size
        assert_includes result.first.fetch("_msg"), "\"message\":\"archive only\""
      ensure
        File.delete("#{path}.0") if path && File.exist?("#{path}.0")
      end

      test "queries json lines emitted by the workflow logger" do
        stdout = StringIO.new
        path = write_log_file
        logger = R3x::WorkflowLog.build_logger(stdout: stdout, path: path)

        logger.tagged("WorkflowLogTest", "r3x.run_active_job_id=aj-123") do
          logger.warn("keep me")
        end
        logger.flush

        result = FileLog.new(path: path).query(
          query: '_msg:"r3x.run_active_job_id=aj-123"',
          start_at: 1.minute.ago,
          end_at: 1.minute.from_now,
          limit: 10
        )

        assert_equal 1, result.size
        assert_includes stdout.string, "[WorkflowLogTest]"
        assert_includes result.first.fetch("_msg"), "\"level\":\"warn\""
        assert_includes result.first.fetch("_msg"), "\"message\":\"keep me\""
        assert_includes result.first.fetch("_msg"), "\"tags\":[\"WorkflowLogTest\",\"r3x.run_active_job_id=aj-123\"]"
      end

      test "raises when the file log is missing" do
        error = assert_raises(Errno::ENOENT) do
          FileLog.new(path: Rails.root.join("tmp", "missing-file-log.log")).query(query: '_msg:"r3x.run_active_job_id=aj-123"')
        end

        assert_includes error.message, "No such file or directory"
      end

      test "raises when the file log is not readable" do
        file = Tempfile.new([ "file-log", ".log" ])
        file.write("{\"level\":\"info\",\"message\":\"hidden\",\"time\":\"2026-04-15T12:00:01.000000Z\",\"tags\":[\"r3x.run_active_job_id=aj-123\"]}\n")
        file.flush
        File.chmod(0o000, file.path)

        error = assert_raises(Errno::EACCES) do
          FileLog.new(path: file.path).query(query: '_msg:"r3x.run_active_job_id=aj-123"')
        end

        assert_includes error.message, "Permission denied"
      ensure
        File.chmod(0o600, file.path) if file
        file.close!
      end

      test "uses workflow log path env when present" do
        workflow_path = write_log_file
        ENV["R3X_WORKFLOW_LOG_PATH"] = workflow_path

        client = FileLog.new

        assert_equal Pathname.new(workflow_path), client.send(:path)
      end

      test "defaults to workflow runs jsonl path for the current environment" do
        ENV.delete("R3X_WORKFLOW_LOG_PATH")

        client = FileLog.new

        assert_equal Rails.root.join("log", "workflow_runs.#{Rails.env}.jsonl"), client.send(:path)
      end

      private
        def write_log_file(*lines)
          file = Tempfile.new([ "file-log", ".log" ])
          lines.each { |line| file.puts(line) }
          file.flush
          @log_files = (@log_files + [ file ]).freeze
          file.path
        end
    end
  end
end

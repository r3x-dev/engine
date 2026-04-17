require "test_helper"

module R3x
  module Dashboard
    class LogsTest < ActiveSupport::TestCase
      class FakeLogsClient
        attr_reader :calls

        def initialize(entries: [], error: nil)
          @entries = entries
          @error = error
          @calls = []
        end

        def query(**kwargs)
          calls << kwargs
          raise error if error

          entries
        end

        private
          attr_reader :entries, :error
      end

      test "returns unavailable state when provider is missing" do
        logs = Logs.new(provider_name: nil)

        result = logs.run_logs(active_job_id: "aj-123")

        assert_equal false, result[:configured]
        assert_empty result[:entries]
      end

      test "returns unavailable state when provider-specific config is missing" do
        original_url = ENV["R3X_VICTORIA_LOGS_URL"]
        ENV.delete("R3X_VICTORIA_LOGS_URL")

        result = Logs.new(provider_name: "victorialogs").run_logs(active_job_id: "aj-123")

        assert_equal false, result[:configured]
        assert_empty result[:entries]
      ensure
        ENV["R3X_VICTORIA_LOGS_URL"] = original_url
      end

      test "queries run logs by run active job id" do
        client = FakeLogsClient.new(entries: [
          {
            "_time" => "2026-04-15T12:00:01Z",
            "_msg" => "[r3x.run_active_job_id=aj-123] hello"
          }
        ])

        run = {
          active_job_id: "aj-123",
          enqueued_at: Time.zone.parse("2026-04-15T12:00:00Z"),
          finished_at: Time.zone.parse("2026-04-15T12:00:30Z")
        }

        result = Logs.new(provider_name: "victorialogs", client: client).run_logs(run)

        assert_equal true, result[:configured]
        assert_nil result[:error]
        assert_equal 1, result[:entries].size
        assert_includes client.calls.first[:query], '_msg:"r3x.run_active_job_id=aj-123"'
      end

      test "run logs strip repeated correlation tags from the message body" do
        client = FakeLogsClient.new(entries: [
          {
            "_time" => "2026-04-15T12:00:01Z",
            "_msg" => "[r3x.run_active_job_id=aj-123] [r3x.workflow_key=test_workflow] [r3x.trigger_key=schedule:123] [Workflows::TestWorkflow] Running workflow trigger_type=schedule",
            "kubernetes.container_name" => "app",
            "kubernetes.pod_name" => "r3x-jobs-123"
          }
        ])

        run = {
          active_job_id: "aj-123",
          class_name: "Workflows::TestWorkflow",
          enqueued_at: Time.zone.parse("2026-04-15T12:00:00Z"),
          finished_at: Time.zone.parse("2026-04-15T12:00:30Z"),
          trigger_key: "schedule:123",
          workflow_key: "test_workflow"
        }

        result = Logs.new(provider_name: "victorialogs", client: client).run_logs(run)
        entry = result[:entries].first

        assert_equal "Running workflow trigger_type=schedule", entry[:message]
        assert_equal [], entry[:tags]
      end

      test "run logs infer severity from normalized message content" do
        client = FakeLogsClient.new(entries: [
          { "_time" => "2026-04-15T12:00:01Z", "_msg" => "Camera alert: driveway offline" },
          { "_time" => "2026-04-15T12:00:02Z", "_msg" => "Retry scheduled after timeout" },
          { "_time" => "2026-04-15T12:00:03Z", "_msg" => "Workflow run completed" },
          { "_time" => "2026-04-15T12:00:04Z", "_msg" => "Still working" }
        ])

        run = {
          active_job_id: "aj-123",
          enqueued_at: Time.zone.parse("2026-04-15T12:00:00Z"),
          finished_at: Time.zone.parse("2026-04-15T12:00:30Z")
        }

        result = Logs.new(provider_name: "victorialogs", client: client).run_logs(run)

        assert_equal %w[danger warn ok muted], result[:entries].map { |entry| entry[:severity] }
      end

      test "returns provider error when provider is unsupported" do
        result = Logs.new(provider_name: "unknown").run_logs(active_job_id: "aj-123")

        assert_equal true, result[:configured]
        assert_equal "Unsupported logs provider: unknown", result[:error]
      end

      test "returns provider error when query fails" do
        client = FakeLogsClient.new(error: Faraday::ConnectionFailed.new("boom"))

        result = Logs.new(provider_name: "victorialogs", client: client).run_logs(active_job_id: "aj-123")

        assert_equal true, result[:configured]
        assert_equal "boom", result[:error]
      end
    end
  end
end

require "test_helper"
require_relative "../../support/fake_change_detecting_trigger"

module R3x
  class RunWorkflowJobTest < ActiveSupport::TestCase
    setup do
      @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
    end

    teardown do
      ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
      WebMock.reset!
    end

    class WorkflowHelper
      include R3x::Concerns::Logger

      def call
        logger.info("hello from helper")
      end
    end

    test "performs workflow with manual trigger" do
      job = RunWorkflowJob.new

      test_workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "TestManual"
        end

        trigger :manual

        def run
          {
            "trigger_type" => ctx.trigger.type.to_s,
            "schedule?" => ctx.trigger.schedule?
          }
        end
      end

      Workflow::Registry.register(test_workflow_class)
      manual_trigger = test_workflow_class.triggers.first

      result = job.perform("test_manual", trigger_key: manual_trigger.unique_key)

      assert_equal "manual", result["trigger_type"]
      refute result["schedule?"]
    ensure
      Workflow::Registry.reset!
    end

    test "performs workflow with schedule trigger" do
      job = RunWorkflowJob.new

      test_workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "TestSchedule"
        end

        trigger :schedule, cron: "0 * * * *"

        def run
          {
            "trigger_type" => ctx.trigger.type.to_s,
            "schedule?" => ctx.trigger.schedule?
          }
        end
      end

      Workflow::Registry.register(test_workflow_class)
      schedule_trigger = test_workflow_class.triggers.first

      result = job.perform("test_schedule", trigger_key: schedule_trigger.unique_key)

      assert_equal "schedule", result["trigger_type"]
      assert result["schedule?"]
    ensure
      Workflow::Registry.reset!
    end

    test "executes workflow through Active Job perform_now" do
      job = RunWorkflowJob.new
      called = nil

      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "TestPerformNow"
        end

        trigger :manual

        def run
          raise "should not be called directly in this test"
        end
      end

      Workflow::Registry.register(workflow_class)
      manual_trigger = workflow_class.triggers.first
      original_perform_now = workflow_class.method(:perform_now)

      workflow_class.singleton_class.send(:define_method, :perform_now) do |*args, **kwargs|
        called = { args: args, kwargs: kwargs }
        { "mode" => "perform_now" }
      end

      result = job.perform("test_perform_now", trigger_key: manual_trigger.unique_key)

      assert_equal({ "mode" => "perform_now" }, result)
      assert_equal [ manual_trigger.unique_key ], called[:args]
      assert_equal({ trigger_payload: nil }, called[:kwargs])
    ensure
      workflow_class.singleton_class.send(:define_method, :perform_now, original_perform_now) if workflow_class && original_perform_now
      Workflow::Registry.reset!
    end

    test "performs workflow with change-detecting trigger and payload" do
      job = RunWorkflowJob.new
      fake_trigger = R3x::TestSupport::FakeChangeDetectingTrigger.new(identity: "feed")

      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "TestChangeDetecting"
        end

        define_singleton_method(:triggers_by_key) { { fake_trigger.unique_key => fake_trigger } }

        def run
          {
            "trigger_type" => ctx.trigger.type.to_s,
            "payload" => ctx.trigger.payload
          }
        end
      end

      Workflow::Registry.register(workflow_class)

      result = job.perform(
        "test_change_detecting",
        trigger_key: fake_trigger.unique_key,
        trigger_payload: { "entries" => [ { "title" => "Hello" } ] }
      )

      assert_equal "fake_change_detecting", result["trigger_type"]
      assert_equal({ entries: [ { title: "Hello" } ] }, result["payload"])
    ensure
      Workflow::Registry.reset!
    end

    test "tags nested workflow execution with workflow and run identifiers" do
      RunWorkflowJob.new
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "TestTaggedLogs"
        end

        trigger :manual

        def run
          WorkflowHelper.new.call
          logger.info("hello from tagged workflow")
        end
      end

      Workflow::Registry.register(workflow_class)
      manual_trigger = workflow_class.triggers.first

      output = capture_logged_output do
        RunWorkflowJob.perform_now("test_tagged_logs", trigger_key: manual_trigger.unique_key)
      end

      assert_includes output, "r3x.run_active_job_id="
      assert_includes output, "r3x.workflow_key=test_tagged_logs"
      assert_includes output, "r3x.trigger_key=#{manual_trigger.unique_key}"
      assert_includes output, "hello from helper"
      assert_includes output, "hello from tagged workflow"
    ensure
      Workflow::Registry.reset!
    end

    test "routes workflow execution logs through the active job logger" do
      web_output = StringIO.new
      workflow_output = StringIO.new
      web_logger = build_test_logger(web_output)
      workflow_logger = build_test_logger(workflow_output)
      original_rails_logger = Rails.logger
      original_active_job_logger = ActiveJob::Base.logger

      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "TestActiveJobLogger"
        end

        trigger :manual

        def run
          WorkflowHelper.new.call
          logger.info("hello from workflow logger")
        end
      end

      Workflow::Registry.register(workflow_class)
      manual_trigger = workflow_class.triggers.first
      Rails.logger = web_logger
      ActiveJob::Base.logger = workflow_logger

      RunWorkflowJob.perform_now("test_active_job_logger", trigger_key: manual_trigger.unique_key)

      assert_includes workflow_output.string, "r3x.run_active_job_id="
      assert_includes workflow_output.string, "r3x.workflow_key=test_active_job_logger"
      assert_includes workflow_output.string, "hello from helper"
      assert_includes workflow_output.string, "hello from workflow logger"
      assert_includes workflow_output.string, "Dispatching workflow class=TestActiveJobLogger"
      refute_includes web_output.string, "hello from helper"
      refute_includes web_output.string, "hello from workflow logger"
      refute_includes web_output.string, "Dispatching workflow class=TestActiveJobLogger"
      assert_same web_logger, R3x::ExecutionLogger.current
    ensure
      Rails.logger = original_rails_logger
      ActiveJob::Base.logger = original_active_job_logger
      Workflow::Registry.reset!
    end

    test "emits workflow jsonl entries readable through the file log client" do
      stdout = StringIO.new
      log_file = Tempfile.new([ "workflow-run", ".jsonl" ])
      log_file.close
      workflow_logger = R3x::WorkflowLog.build_logger(stdout: stdout, path: log_file.path)
      original_active_job_logger = ActiveJob::Base.logger

      workflow_class = Class.new(R3x::Workflow::Base) do
        class << self
          # rubocop:disable ThreadSafety/ClassAndModuleAttributes
          attr_accessor :last_run_job_id
          # rubocop:enable ThreadSafety/ClassAndModuleAttributes
        end

        def self.name
          "TestWorkflowJsonl"
        end

        trigger :manual

        def run
          self.class.last_run_job_id = job_id
          logger.info("hello from workflow jsonl")
        end
      end

      Workflow::Registry.register(workflow_class)
      manual_trigger = workflow_class.triggers.first
      ActiveJob::Base.logger = workflow_logger

      RunWorkflowJob.perform_now("test_workflow_jsonl", trigger_key: manual_trigger.unique_key)
      workflow_logger.flush

      entries = R3x::Client::FileLog.new(path: log_file.path).query(
        query: %(_msg:"r3x.run_active_job_id=#{workflow_class.last_run_job_id}"),
        start_at: 1.minute.ago,
        end_at: 1.minute.from_now,
        limit: 20
      )

      assert entries.any? { |entry| entry.fetch("_msg").include?("\"message\":\"hello from workflow jsonl\"") }
      assert entries.any? { |entry| entry.fetch("_msg").include?("\"message\":\"Workflow run completed\"") }
      assert_includes stdout.string, "hello from workflow jsonl"
    ensure
      log_file.close! if log_file
      ActiveJob::Base.logger = original_active_job_logger
      Workflow::Registry.reset!
    end

    test "logs workflow dispatch failures" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "TestDispatchLogs"
        end

        trigger :manual

        def run
          raise ArgumentError, "boom"
        end
      end

      Workflow::Registry.register(workflow_class)
      manual_trigger = workflow_class.triggers.first

      output = capture_logged_output do
        assert_raises(ArgumentError) do
          RunWorkflowJob.perform_now("test_dispatch_logs", trigger_key: manual_trigger.unique_key)
        end
      end

      assert_includes output, "Dispatching workflow class=TestDispatchLogs"
      assert_includes output, "r3x.job_outcome=failed"
      assert_includes output, "Workflow dispatch failed"
    ensure
      Workflow::Registry.reset!
    end

    private
  end
end

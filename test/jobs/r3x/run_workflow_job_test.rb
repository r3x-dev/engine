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

      workflow_class.stubs(:perform_now)
        .with(manual_trigger.unique_key, trigger_payload: nil)
        .returns({ "mode" => "perform_now" })

      result = job.perform("test_perform_now", trigger_key: manual_trigger.unique_key)

      assert_equal({ "mode" => "perform_now" }, result)
    ensure
      Workflow::Registry.reset!
    end

    test "performs workflow with change-detecting trigger and payload" do
      job = RunWorkflowJob.new
      fake_trigger = R3x::TestSupport::FakeChangeDetectingTrigger.new(identity: "feed")

      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "TestChangeDetecting"
        end

        def run
          {
            "trigger_type" => ctx.trigger.type.to_s,
            "payload" => ctx.trigger.payload
          }
        end
      end

      workflow_class.stubs(:triggers_by_key).returns({ fake_trigger.unique_key => fake_trigger })
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
      job = RunWorkflowJob.new
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "TestTaggedLogs"
        end

        trigger :manual

        def run
          Rails.logger.info("hello from tagged workflow")
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
      assert_includes output, "hello from tagged workflow"
    ensure
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

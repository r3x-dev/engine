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
  end
end

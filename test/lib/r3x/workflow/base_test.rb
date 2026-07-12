# frozen_string_literal: true

require "test_helper"

module R3x
  class WorkflowBaseTest < ActiveSupport::TestCase
    # Default trigger behavior tests

    test "returns default Manual trigger when no triggers declared" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NoTriggers"
        end
      end

      triggers = klass.triggers

      assert_equal 1, triggers.size
      assert_equal :manual, triggers.first.type
    end

    test "returns declared triggers when triggers are declared" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::WithTriggers"
        end

        trigger :manual
      end

      triggers = klass.triggers

      assert_equal 1, triggers.size
      assert_equal :manual, triggers.first.type
    end

    test "perform does not fallback to manual trigger for unknown trigger key" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::StrictTriggerLookup"
        end

        trigger :manual

        def run
          raise "should not execute"
        end
      end

      error = assert_raises(ArgumentError) do
        workflow_class.perform_now("missing-trigger")
      end

      assert_match(/Unknown trigger key 'missing-trigger'/, error.message)
    end

    test "perform accepts auto-generated manual trigger when no triggers are declared" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ImplicitManual"
        end

        def run
          { "trigger_type" => ctx.trigger.type.to_s }
        end
      end

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal "manual", result["trigger_type"]
    end

    test "perform without trigger key uses manual trigger for schedule-only workflow" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ManualFallback"
        end

        trigger :schedule, cron: "0 * * * *"

        def run
          { "trigger_type" => ctx.trigger.type.to_s }
        end
      end

      result = workflow_class.perform_now

      assert_equal "manual", result["trigger_type"]
    end

    test "perform exposes ctx helper to workflows" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ContextHelper"
        end

        trigger :manual

        def run
          { "trigger_type" => ctx.trigger.type.to_s }
        end
      end

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal "manual", result["trigger_type"]
    end

    test "on_complete runs after successful run" do
      events = []
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::CompletionWorkflow"
        end

        trigger :manual
        on_complete { events << :complete }

        define_method :run do
          events << :run
          { "status" => "ran" }
        end
      end

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal({ "status" => "ran" }, result)
      assert_equal %i[run complete], events
    end

    test "on_complete runs multiple blocks in declaration order" do
      events = []
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::MultipleCompletionWorkflow"
        end

        trigger :manual
        on_complete { events << :first }
        on_complete { events << :second }

        define_method :run do
          events << :run
        end
      end

      workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal %i[run first second], events
    end

    test "on_complete can access ctx" do
      events = []
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::CompletionContextWorkflow"
        end

        trigger :manual
        on_complete { events << ctx.trigger.type }

        def run
          { "status" => "ran" }
        end
      end

      workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal [:manual], events
    end

    test "on_complete does not run when condition skips workflow" do
      events = []
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::SkippedCompletionWorkflow"
        end

        trigger :manual
        condition :ready?, reason: "Not ready"
        on_complete { events << :complete }

        define_method :run do
          events << :run
        end

        private

        def ready?
          false
        end
      end

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal({ "status" => "skipped", "reason" => "Not ready" }, result)
      assert_empty events
    end

    test "on_complete failure raises and marks workflow failed" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::FailingCompletionWorkflow"
        end

        trigger :manual
        on_complete { raise ArgumentError, "completion failed" }

        def run
          { "status" => "ran" }
        end
      end

      output = capture_logged_output do
        error = assert_raises(ArgumentError) do
          workflow_class.perform_now(workflow_class.triggers.first.unique_key)
        end
        assert_equal "completion failed", error.message
      end

      assert_includes output, "r3x.job_outcome=failed"
      assert_includes output, "Workflow run failed"
      assert_not_includes output, "Workflow run completed"
    end

    test "on_complete does not run when workflow is interrupted before completion" do
      events = []
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::InterruptedCompletionWorkflow"
        end

        trigger :manual
        on_complete { events << :complete }

        define_method :run do
          step :first do
            events << :first
          end

          step :second, isolated: true do
            events << :second
          end
        end
      end

      workflow = workflow_class.new
      assert_raises(ActiveJob::Continuation::Interrupt) do
        workflow.perform(workflow_class.triggers.first.unique_key)
      end

      assert_equal [:first], events
    end

    test "perform logs 'Resuming workflow' instead of 'Running workflow' on resumption" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::InterruptedResumptionWorkflow"
        end

        trigger :manual

        define_method :run do
          step :first do
          end

          step :second, isolated: true do
          end

          step :third do
          end
        end
      end

      begin
        Workflows.const_set(:InterruptedResumptionWorkflow, workflow_class)

        workflow = workflow_class.new
        trigger_key = workflow_class.triggers.first.unique_key

        output1 = capture_logged_output do
          assert_raises(ActiveJob::Continuation::Interrupt) do
            workflow.perform(trigger_key)
          end
        end

        assert_includes output1, "Running workflow trigger_type=manual"
        assert_not_includes output1, "Resuming workflow trigger_type=manual"

        serialized_job_data = workflow.serialize
        resumed_workflow = workflow_class.deserialize(serialized_job_data)

        output2 = capture_logged_output do
          assert_raises(ActiveJob::Continuation::Interrupt) do
            resumed_workflow.perform(trigger_key)
          end
        end

        assert_not_includes output2, "Running workflow trigger_type=manual"
        assert_includes output2, "Resuming workflow trigger_type=manual after 'first'"
      ensure
        Workflows.send(:remove_const, :InterruptedResumptionWorkflow) if Workflows.const_defined?(:InterruptedResumptionWorkflow)
      end
    end

    test "perform does not reload workflow packs" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NoPackReload"
        end

        trigger :manual

        def run
          { "trigger_type" => ctx.trigger.type.to_s }
        end
      end

      R3x::Workflow::PackLoader.stubs(:load!).raises("should not reload packs during workflow execution")

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal "manual", result["trigger_type"]
    end

    test "condition returns skipped result before running workflow when predicate is false" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::SkippedWorkflow"
        end

        trigger :manual
        condition :ready?, reason: "Not ready"

        def run
          raise "should not execute"
        end

        private

        def ready?
          false
        end
      end

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal({ "status" => "skipped", "reason" => "Not ready" }, result)
    end

    test "condition allows workflow when predicate is true" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::AllowedWorkflow"
        end

        trigger :manual
        condition :ready?, reason: "Not ready"

        def run
          { "status" => "ran" }
        end

        private

        def ready?
          true
        end
      end

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal({ "status" => "ran" }, result)
    end

    test "condition stops at the first unmet condition" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::MultiSkipWorkflow"
        end

        trigger :manual
        condition :first_ready?, reason: "First reason"
        condition :second_ready?, reason: "Second reason"

        def run
          raise "should not execute"
        end

        private

        def first_ready?
          false
        end

        def second_ready?
          raise "should not evaluate"
        end
      end

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal({ "status" => "skipped", "reason" => "First reason" }, result)
    end

    test "condition is not evaluated on continuation resumes" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ResumedWorkflow"
        end

        trigger :manual
        condition :ready?, reason: "Not ready"

        def run
          { "status" => "resumed" }
        end

        private

        def ready?
          raise "should not evaluate"
        end
      end

      workflow = workflow_class.new
      workflow.continuation = ActiveJob::Continuation.new(workflow, "completed" => ["previous_step"])

      result = workflow.perform(workflow_class.triggers.first.unique_key)

      assert_equal({ "status" => "resumed" }, result)
    end

    test "perform logs workflow run outcome" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::LoggedWorkflow"
        end

        trigger :manual

        def run
          { "status" => "ok" }
        end
      end

      output = capture_logged_output do
        workflow_class.perform_now(workflow_class.triggers.first.unique_key)
      end

      assert_includes output, "Running workflow trigger_type=manual"
      assert_includes output, "r3x.run_active_job_id="
      assert_includes output, "r3x.trigger_key="
      assert_not_includes output, "r3x.workflow_key=logged_workflow"
      assert_includes output, "r3x.job_outcome=success"
      assert_includes output, "Workflow run completed"
    end

    test "perform logs workflow failure outcome" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::FailingWorkflow"
        end

        trigger :manual

        def run
          raise ArgumentError, "boom"
        end
      end

      output = capture_logged_output do
        assert_raises(ArgumentError) do
          workflow_class.perform_now(workflow_class.triggers.first.unique_key)
        end
      end

      assert_includes output, "r3x.job_outcome=failed"
      assert_includes output, "Workflow run failed"
      assert_match(/(?:"error_class":"ArgumentError"|error_class=ArgumentError)/, output)
      assert_match(/(?:"error_message":"boom"|error_message=boom)/, output)

      failure_payload = output.lines
        .map { |line| MultiJSON.parse(line) }
        .find { |payload| payload["error_class"] == "ArgumentError" && payload["error_message"] == "boom" }

      assert_equal "Workflow run failed", failure_payload.fetch("message")
      assert_equal "ArgumentError", failure_payload.fetch("error_class")
      assert_equal "boom", failure_payload.fetch("error_message")
      assert_instance_of Array, failure_payload.fetch("backtrace")
    end

    test "prevents overriding perform method in subclasses" do
      error = assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Workflows::BadWorkflow"
          end

          def perform
            # This should raise an error
          end
        end
      end

      assert_match(/Do not override #perform/, error.message)
      assert_match(/Override #run instead/, error.message)
    end

    test "schedulable_triggers excludes auto-generated Manual triggers" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NoExplicitTriggers"
        end
      end

      # Should return empty array, not the auto-generated Manual trigger
      assert_empty klass.schedulable_triggers
    end

    test "triggers_by_key excludes auto-generated Manual triggers" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NoExplicitTriggers"
        end
      end

      # Should return empty hash, not the auto-generated Manual trigger
      assert_empty klass.triggers_by_key
    end
  end
end

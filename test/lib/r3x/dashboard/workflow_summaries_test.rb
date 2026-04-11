require "test_helper"
require_relative "../../../support/fake_change_detecting_trigger"

module R3x
  module Dashboard
    class WorkflowSummariesTest < ActiveSupport::TestCase
      setup do
        @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
        ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
        Workflow::PackLoader.load!(force: true)
        clear_tables
      end

      teardown do
        clear_tables
        ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
        Workflow::Registry.reset!
      end

      test "builds summary with recurring task and healthy status" do
        workflow_class = Workflow::Registry.fetch("test_workflow")
        trigger = workflow_class.triggers.first
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:#{trigger.unique_key}",
          schedule: trigger.cron,
          class_name: workflow_class.name,
          arguments: [ trigger.unique_key ],
          queue_name: "default",
          static: false
        )
        SolidQueue::Job.create!(
          queue_name: "default",
          class_name: workflow_class.name,
          arguments: [ trigger.unique_key ],
          finished_at: 1.minute.ago,
          created_at: 10.minutes.ago,
          updated_at: 1.minute.ago
        )

        summary = WorkflowSummaries.new.find!("test_workflow")

        assert_equal "Healthy", summary[:health][:label]
        assert summary[:next_trigger_at].present?
        assert_equal 1, summary[:trigger_entries].size
        assert summary[:trigger_entries].first[:recurring_task].present?
      end

      test "prefers trigger error health over last run status" do
        fake_trigger = R3x::TestSupport::FakeChangeDetectingTrigger.new(identity: "feed")
        workflow_class = Class.new(R3x::Workflow::Base) do
          def self.name
            "TestDashboardChangeFeed"
          end

          define_singleton_method(:triggers) { [ fake_trigger ] }
          define_singleton_method(:schedulable_triggers) { [ fake_trigger ] }
          define_singleton_method(:triggers_by_key) { { fake_trigger.unique_key => fake_trigger } }

          def run
          end
        end

        Workflow::Registry.register(workflow_class)
        R3x::TriggerState.create!(
          workflow_key: workflow_class.workflow_key,
          trigger_key: fake_trigger.unique_key,
          trigger_type: fake_trigger.type.to_s,
          state: {},
          last_error_at: Time.current,
          last_error_message: "feed offline"
        )

        summary = WorkflowSummaries.new.find!(workflow_class.workflow_key)

        assert_equal "Trigger error", summary[:health][:label]
        assert_equal "feed offline", summary[:health][:detail]
      end

      private
        def clear_tables
          SolidQueue::RecurringTask.delete_all
          SolidQueue::FailedExecution.delete_all
          SolidQueue::Job.delete_all
          R3x::TriggerState.delete_all
        end
    end
  end
end

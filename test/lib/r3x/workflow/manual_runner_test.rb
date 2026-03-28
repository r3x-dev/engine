require "test_helper"

module R3x
  module Workflow
    class ManualRunnerTest < ActiveSupport::TestCase
      setup do
        @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
        ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
      end

      teardown do
        ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
        Workflow::Registry.reset!
      end

      test "runs schedule-only workflow through manual trigger" do
        workflow_class = Class.new(R3x::Workflow::Base) do
          def self.name
            "Workflows::ScheduleOnlyManualRun"
          end

          trigger :schedule, cron: "0 * * * *"

          def run(ctx)
            { "trigger_type" => ctx.trigger.type.to_s }
          end
        end

        Workflow::Registry.register(workflow_class)

        result = ManualRunner.run("schedule_only_manual_run")

        assert_equal "manual", result["trigger_type"]
      end
    end
  end
end

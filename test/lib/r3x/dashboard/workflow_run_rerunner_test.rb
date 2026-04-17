require "test_helper"

module R3x
  module Dashboard
    class WorkflowRunRerunnerTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper

      setup do
        clear_enqueued_jobs
      end

      teardown do
        clear_enqueued_jobs
      end

      test "enqueue reruns terminal known workflow runs with original trigger payload" do
        run = {
          known_workflow: true,
          status: "finished",
          workflow_key: "test_workflow",
          trigger_key: "schedule:123",
          trigger_payload: { "id" => "42" },
          queue_name: "critical",
          priority: 9
        }

        assert_enqueued_with(
          job: R3x::RunWorkflowJob,
          args: [ "test_workflow", { trigger_key: "schedule:123", trigger_payload: { "id" => "42" } } ],
          queue: "critical",
          priority: 9
        ) do
          WorkflowRunRerunner.new(run: run).enqueue!
        end
      end

      test "enqueue reruns without queue metadata when not present" do
        run = {
          known_workflow: true,
          status: "failed",
          workflow_key: "test_workflow",
          trigger_key: nil,
          trigger_payload: nil,
          queue_name: nil,
          priority: nil
        }

        assert_enqueued_with(
          job: R3x::RunWorkflowJob,
          args: [ "test_workflow", { trigger_key: nil, trigger_payload: nil } ]
        ) do
          WorkflowRunRerunner.new(run: run).enqueue!
        end
      end

      test "enqueue raises for unknown workflow runs" do
        run = { known_workflow: false, status: "finished" }

        assert_raises(ArgumentError) do
          WorkflowRunRerunner.new(run: run).enqueue!
        end
      end

      test "enqueue raises for non terminal workflow runs" do
        run = { known_workflow: true, status: "running" }

        assert_raises(ArgumentError) do
          WorkflowRunRerunner.new(run: run).enqueue!
        end
      end
    end
  end
end

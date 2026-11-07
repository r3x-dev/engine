# frozen_string_literal: true

require "test_helper"

class Dashboard::DirectWorkflowEnqueuerTest < ActiveSupport::TestCase
  setup do
    TestDbCleanup.clear_runtime_tables!
  end

  teardown do
    TestDbCleanup.clear_runtime_tables!
  end

  test "web enqueue persists an admission request without resolving the workflow class" do
    request = nil

    assert_difference -> { SolidQueue::Job.where(class_name: "R3x::Workflow::EnqueueJob").count }, 1 do
      request = Dashboard::DirectWorkflowEnqueuer.enqueue!(
        class_name: "Workflows::NotMounted",
        arguments: ["scheduled", { "trigger_payload" => { "id" => "42" }, "_aj_symbol_keys" => ["trigger_payload"] }],
        queue_name: "critical",
        priority: 7,
      )
    end

    assert_equal "critical", request.queue_name
    assert_equal 7, request.priority
    assert_equal ["scheduled", { trigger_payload: { "id" => "42" } }], request.workflow_arguments.second
    assert_empty SolidQueue::Job.where(class_name: "Workflows::NotMounted")
  end

  test "request query filters targets before its history limit and excludes ordinary jobs" do
    request = Dashboard::DirectWorkflowEnqueuer.enqueue!(class_name: "Workflows::NotMounted", arguments: [], queue_name: "default", priority: 0)
    12.times do
      Dashboard::DirectWorkflowEnqueuer.enqueue!(class_name: "Workflows::Unrelated", arguments: [], queue_name: "default", priority: 0)
    end

    matching = Dashboard::EnqueueRequest.for_workflow(["Workflows::NotMounted"]).order(id: :desc).limit(10)

    assert_equal [request.id], matching.pluck(:id)
    assert_empty Dashboard::Run.direct_workflows
    assert_empty R3x::Dashboard::Workflow::Catalog.new.workflow_keys
    assert_empty R3x::Dashboard::Workflow::Runs.new.all
  end
end

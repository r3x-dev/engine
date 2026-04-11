require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
    ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
    R3x::Workflow::PackLoader.load!(force: true)
    clear_tables

    workflow_class = R3x::Workflow::Registry.fetch("test_workflow")
    @trigger = workflow_class.triggers.first
    SolidQueue::RecurringTask.create!(
      key: "workflow:test_workflow:#{@trigger.unique_key}",
      schedule: @trigger.cron,
      class_name: workflow_class.name,
      arguments: [ @trigger.unique_key ],
      queue_name: "default",
      static: false
    )
    @job = SolidQueue::Job.create!(
      queue_name: "default",
      class_name: workflow_class.name,
      arguments: [ @trigger.unique_key ],
      finished_at: 1.minute.ago,
      created_at: 10.minutes.ago,
      updated_at: 1.minute.ago
    )
    R3x::TriggerState.create!(
      workflow_key: "test_workflow",
      trigger_key: @trigger.unique_key,
      trigger_type: "schedule",
      state: {},
      last_checked_at: 2.minutes.ago,
      last_triggered_at: 1.minute.ago
    )
  end

  teardown do
    clear_tables
    ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
    R3x::Workflow::Registry.reset!
  end

  test "root renders workflows dashboard" do
    get "/"

    assert_response :success
    assert_includes response.body, "R3x Dashboard"
    assert_includes response.body, "Test Workflow"
    assert_includes response.body, "/ops/jobs"
  end

  test "workflow detail renders trigger state and recent runs" do
    get "/workflows/test_workflow"

    assert_response :success
    assert_includes response.body, "Latest visible run"
    assert_includes response.body, @trigger.unique_key
    assert_includes response.body, "Last checked"
  end

  test "recent runs supports filtering" do
    failed_job = SolidQueue::Job.create!(
      queue_name: "default",
      class_name: R3x::Workflow::Registry.fetch("test_workflow").name,
      arguments: [ @trigger.unique_key ],
      created_at: 5.minutes.ago,
      updated_at: 30.seconds.ago
    )
    SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "boom", created_at: 30.seconds.ago)

    get "/workflow-runs", params: { workflow: "test_workflow", status: "failed" }

    assert_response :success
    assert_includes response.body, "Recent Runs"
    assert_includes response.body, "boom"
    refute_match(/No workflow runs match/, response.body)
  end

  test "ops jobs route stays available" do
    get "/ops/jobs"

    assert_response :success
  end

  private
    def clear_tables
      SolidQueue::RecurringTask.delete_all
      SolidQueue::BlockedExecution.delete_all
      SolidQueue::ClaimedExecution.delete_all
      SolidQueue::FailedExecution.delete_all
      SolidQueue::ReadyExecution.delete_all
      SolidQueue::ScheduledExecution.delete_all
      SolidQueue::Job.delete_all
      R3x::TriggerState.delete_all
    end
end

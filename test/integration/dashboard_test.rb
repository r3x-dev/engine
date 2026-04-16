require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  WORKFLOW_JOB_CLASS_NAME = R3x::TestSupport::DashboardWorkflowJob.name.freeze

  setup do
    @original_logs_provider = ENV["R3X_LOGS_PROVIDER"]
    @original_victoria_logs_url = ENV["R3X_VICTORIA_LOGS_URL"]
    clear_tables
    clear_enqueued_jobs
    @trigger = "schedule:abc123".freeze
    SolidQueue::RecurringTask.create!(
      key: "workflow:test_workflow:#{@trigger}",
      schedule: "0 * * * *",
      class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      queue_name: "default",
      static: false
    )
    @job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      active_job_id: "aj-123",
      finished_at: 1.minute.ago,
      created_at: 10.minutes.ago,
      updated_at: 1.minute.ago
    )
    R3x::TriggerState.create!(
      workflow_key: "test_workflow",
      trigger_key: @trigger,
      trigger_type: "schedule",
      state: {},
      last_checked_at: 2.minutes.ago,
      last_triggered_at: 1.minute.ago
    )
  end

  teardown do
    ENV["R3X_LOGS_PROVIDER"] = @original_logs_provider
    ENV["R3X_VICTORIA_LOGS_URL"] = @original_victoria_logs_url
  end

  test "root renders workflows dashboard" do
    get "/"

    assert_response :success
    assert_includes response.body, "R3x Dashboard"
    assert_includes response.body, "Test Workflow"
    assert_includes response.body, "Workflow runtime from the database"
    assert_includes response.body, "Run now"
  end

  test "workflow detail renders trigger state and recent runs" do
    ENV.delete("R3X_LOGS_PROVIDER")

    get "/workflows/test_workflow"

    assert_response :success
    assert_includes response.body, "Triggers"
    assert_includes response.body, @trigger
    assert_includes response.body, "Last checked"
    assert_includes response.body, "Run now"
    refute_includes response.body, "Recent logs"
  end

  test "workflow detail shows latest failure shortcut when a failed run exists" do
    failed_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: 5.minutes.ago,
      updated_at: 30.seconds.ago
    )
    SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "boom", created_at: 30.seconds.ago)

    get "/workflows/test_workflow"

    assert_response :success
    assert_includes response.body, "Latest failure"
    assert_includes response.body, "/workflow-runs/#{failed_job.id}"
  end

  test "workflows index links last run to run details when the latest run failed" do
    failed_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: 5.minutes.ago,
      updated_at: 30.seconds.ago
    )
    SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "boom", created_at: 30.seconds.ago)

    get "/"

    assert_response :success
    assert_includes response.body, "Failed"
    assert_includes response.body, "/workflow-runs/#{failed_job.id}"
  end

  test "recent runs supports filtering" do
    failed_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: 5.minutes.ago,
      updated_at: 30.seconds.ago
    )
    SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "boom", created_at: 30.seconds.ago)

    get "/workflow-runs", params: { workflow: "test_workflow", status: "failed" }

    assert_response :success
    assert_includes response.body, "Recent Runs"
    assert_includes response.body, "Back to workflow"
    assert_includes response.body, "boom"
    refute_match(/No workflow runs match/, response.body)
  end

  test "workflow run detail shows full error and navigation" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    failed_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: 5.minutes.ago,
      updated_at: 30.seconds.ago
    )
    SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "boom\nstack line 1\nstack line 2", created_at: 30.seconds.ago)

    get "/workflow-runs/#{failed_job.id}", params: { logs: 1 }

    assert_response :success
    assert_includes response.body, "Failure Details"
    assert_includes response.body, "Run logs"
    assert_includes response.body, "stack line 1"
    assert_includes response.body, "Back to workflow"
    assert_includes response.body, '<section class="panel stack" style="margin-top: 18px;">'
  end

  test "workflow run detail renders compact log messages without repeated correlation tags" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
      .to_return(
        status: 200,
        body: {
          "_time" => "2026-04-15T12:00:01Z",
          "_msg" => "[r3x.run_active_job_id=#{@job.active_job_id}] [r3x.workflow_key=test_workflow] [r3x.trigger_key=#{@trigger}] [#{WORKFLOW_JOB_CLASS_NAME}] Running workflow trigger_type=schedule",
          "kubernetes.container_name" => "app",
          "kubernetes.pod_name" => "r3x-jobs-123"
        }.to_json + "\n"
      )

    get "/workflow-runs/#{@job.id}", params: { logs: 1 }

    assert_response :success
    assert_includes response.body, "Running workflow trigger_type=schedule"
    assert_includes response.body, "r3x-jobs-123 / app"
    refute_includes response.body, "[r3x.run_active_job_id="
    refute_includes response.body, "[r3x.workflow_key=test_workflow]"
    refute_includes response.body, "[#{WORKFLOW_JOB_CLASS_NAME}]"
  end

  test "workflow run detail shows log placeholder before loading" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
      .to_return(status: 200, body: "")

    get "/workflow-runs/#{@job.id}"

    assert_response :success
    assert_includes response.body, "Run logs"
    assert_includes response.body, "Load logs"
    assert_includes response.body, "logs-placeholder"
    refute_includes response.body, "Hide logs"
    refute_includes response.body, "No indexed logs were found for this run in its execution window."
  end

  test "recent runs shows log shortcut when logs are configured" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    get "/workflow-runs"

    assert_response :success
    assert_includes response.body, "View logs"
  end

  test "recent runs hides log shortcut when provider-specific config is missing" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV.delete("R3X_VICTORIA_LOGS_URL")

    get "/workflow-runs"

    assert_response :success
    refute_includes response.body, "View logs"
  end

  test "workflow run detail reports unsupported log provider" do
    ENV["R3X_LOGS_PROVIDER"] = "unknown"

    get "/workflow-runs/#{@job.id}", params: { logs: 1 }

    assert_response :success
    assert_includes response.body, "Log query failed: Unsupported logs provider: unknown"
  end

  test "workflow detail does not show logs shortcut" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    get "/workflows/test_workflow"

    assert_response :success
    refute_includes response.body, "Load logs"
    refute_includes response.body, "Hide logs"
    refute_includes response.body, "Recent logs"
  end

  test "workflow detail recent runs lead with trigger and omit workflow queue columns" do
    get "/workflows/test_workflow"

    assert_response :success
    assert_match(/<th>Trigger<\/th>.*<th>Status<\/th>.*<th>Observed<\/th>.*<th>Details<\/th>/m, response.body)
    refute_includes response.body, "<th>Workflow</th>"
    refute_includes response.body, "<th>Queue</th>"
  end

  test "ops jobs route stays available" do
    get "/ops/jobs"

    assert_response :success
  end

  test "workflow detail can enqueue run now from recurring task" do
    assert_enqueued_jobs 1, only: R3x::RunWorkflowJob do
      post "/workflows/test_workflow/run_trigger"
    end

    assert_redirected_to "/workflows/test_workflow"
  end

  test "workflow detail can enqueue run now for change detection task" do
    SolidQueue::RecurringTask.create!(
      key: "workflow:feed_watch:feed:123",
      schedule: "*/5 * * * *",
      class_name: "R3x::ChangeDetectionJob",
      arguments: [ "feed_watch", { "trigger_key" => "feed:123" } ],
      queue_name: "feed",
      static: false
    )

    assert_enqueued_jobs 1, only: R3x::ChangeDetectionJob do
      post "/workflows/feed_watch/run_trigger", params: { trigger_key: "feed:123" }
    end

    assert_redirected_to "/workflows/feed_watch"
  end

  private
    def clear_tables
      TestDbCleanup.clear_runtime_tables!
    end
end

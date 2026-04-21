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

    stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
      .to_return(status: 200, body: "")

    get "/workflow-runs/#{failed_job.id}"

    assert_response :success
    assert_includes response.body, "Failure Details"
    assert_includes response.body, "Run logs"
    assert_includes response.body, "stack line 1"
    assert_includes response.body, "Back to workflow"
    assert_includes response.body, 'class="panel stack panel-spaced"'
    assert_match(/<span class="label">Finished<\/span>\s*<strong><time[^>]*>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, response.body)
  end

  test "workflow run detail hides failure details when run succeeded" do
    get "/workflow-runs/#{@job.id}"

    assert_response :success
    refute_includes response.body, "Failure Details"
    refute_includes response.body, "No error details were recorded for this run."
  end

  test "workflow run detail shows absolute metadata timestamps" do
    get "/workflow-runs/#{@job.id}"

    assert_response :success
    assert_includes response.body, "Run Details"
    assert_match(/<span class="label">Enqueued<\/span>\s*<strong><time[^>]*>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, response.body)
    refute_match(/<span class="label">Enqueued<\/span>\s*<strong><time[^>]*>about /, response.body)
    assert_match(/<span class="label">Finished<\/span>\s*<strong><time[^>]*>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, response.body)
    refute_includes response.body, "Recorded"
  end

  test "workflow run detail hides finished timestamp for non-terminal runs" do
    queued_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: 30.seconds.ago,
      updated_at: 30.seconds.ago
    )

    get "/workflow-runs/#{queued_job.id}"

    assert_response :success
    refute_match(/<span class="label">Finished<\/span>/, response.body)
  end

  test "workflow run detail shows rerun action for terminal runs" do
    get "/workflow-runs/#{@job.id}"

    assert_response :success
    assert_includes response.body, "Rerun"
    assert_includes response.body, "/workflow-runs/#{@job.id}/rerun"
  end

  test "workflow run detail hides rerun action for non-terminal runs" do
    queued_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: 30.seconds.ago,
      updated_at: 30.seconds.ago
    )

    get "/workflow-runs/#{queued_job.id}"

    assert_response :success
    refute_includes response.body, "Rerun"
    refute_includes response.body, "/workflow-runs/#{queued_job.id}/rerun"
  end

  test "workflow run rerun returns not found for non-terminal runs" do
    queued_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: 30.seconds.ago,
      updated_at: 30.seconds.ago
    )

    post "/workflow-runs/#{queued_job.id}/rerun"

    assert_response :not_found
  end

  test "workflow run detail rerun enqueues run workflow job with original payload" do
    payload = { "article_id" => "42", "change" => "updated" }
    rerun_source_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger, { trigger_payload: payload } ],
      queue_name: "critical",
      finished_at: 10.seconds.ago,
      created_at: 2.minutes.ago,
      updated_at: 10.seconds.ago
    )

    assert_enqueued_with(
      job: R3x::RunWorkflowJob,
      args: [ "test_workflow", { trigger_key: @trigger, trigger_payload: payload } ],
      queue: "critical",
      priority: 0
    ) do
      post "/workflow-runs/#{rerun_source_job.id}/rerun"
    end

    assert_redirected_to "/workflow-runs/#{rerun_source_job.id}"
  end

  test "workflow run detail renders compact log messages without repeated correlation tags" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
      .to_return(
        status: 200,
        body: {
          "_time" => "2026-04-15T12:00:01Z",
          "_msg" => MultiJson.dump(
            "level" => "info",
            "message" => "[r3x.run_active_job_id=#{@job.active_job_id}] [r3x.workflow_key=test_workflow] [r3x.trigger_key=#{@trigger}] [#{WORKFLOW_JOB_CLASS_NAME}] Running workflow trigger_type=schedule"
          ),
          "kubernetes.container_name" => "app",
          "kubernetes.pod_name" => "r3x-jobs-123"
        }.to_json + "\n"
      )

    get "/workflow-runs/#{@job.id}"

    assert_response :success
    assert_includes response.body, "Running workflow trigger_type=schedule"
    assert_includes response.body, "12:00:01"
    assert_includes response.body, "log-time"
    assert_includes response.body, "log-message"
    assert_includes response.body, "log-level"
    assert_includes response.body, "INFO"
    refute_includes response.body, "log-meta"
    refute_includes response.body, "r3x-jobs-123 / app"
    refute_includes response.body, "[r3x.run_active_job_id="
    refute_includes response.body, "[r3x.workflow_key=test_workflow]"
    refute_includes response.body, "[#{WORKFLOW_JOB_CLASS_NAME}]"
  end

  test "workflow run detail renders logs immediately when configured" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
      .to_return(status: 200, body: "")

    get "/workflow-runs/#{@job.id}"

    assert_response :success
    assert_includes response.body, "Run logs"
    assert_includes response.body, "No indexed logs were found for this run in its execution window."
    refute_includes response.body, "Hide logs"
    refute_includes response.body, "Load logs"
    assert_select "section.logs-placeholder-panel", count: 0
  end

  test "running workflow run logs show waiting state before first line arrives" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    running_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      active_job_id: "aj-running-empty",
      created_at: 1.minute.ago,
      updated_at: 30.seconds.ago
    )
    claim_job!(running_job)

    stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
      .to_return(status: 200, body: "")

    get "/workflow-runs/#{running_job.id}"

    assert_response :success
    assert_includes response.body, "Waiting for first log line..."
    assert_includes response.body, "Last updated --:--:--"
  end

  test "running workflow run logs auto-refresh while visible" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    running_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      active_job_id: "aj-running",
      created_at: 1.minute.ago,
      updated_at: 30.seconds.ago
    )
    claim_job!(running_job)

    stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
      .to_return(
        status: 200,
        body: {
          "_time" => "2026-04-15T12:00:01Z",
          "_msg" => MultiJson.dump("level" => "info", "message" => "[r3x.run_active_job_id=aj-running] Still working")
        }.to_json + "\n"
      )

    get "/workflow-runs/#{running_job.id}"

    assert_response :success
    assert_includes response.body, 'data-r3x-log-refresh="true"'
    assert_includes response.body, "data-r3x-log-refresh-select"
    assert_includes response.body, "data-r3x-log-live-indicator"
    assert_includes response.body, "Live"
    assert_includes response.body, 'value="30s" selected="selected"'
    assert_includes response.body, "data-r3x-log-last-updated"
    assert_includes response.body, "12:00:01"
    assert_includes response.body, "Every 30s while running"
    assert_includes response.body, "/workflow-runs/#{running_job.id}/logs"
    assert_includes response.body, "Still working"
  end

  test "terminal workflow run logs do not auto-refresh" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
      .to_return(status: 200, body: "")

    get "/workflow-runs/#{@job.id}"

    assert_response :success
    assert_includes response.body, 'data-r3x-log-refresh="false"'
    assert_select "select[data-r3x-log-refresh-select]", count: 0
    assert_select "[data-r3x-log-refresh-status]", count: 0
  end

  test "workflow run logs endpoint renders only refreshable panel" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    running_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      active_job_id: "aj-running-panel",
      created_at: 1.minute.ago,
      updated_at: 30.seconds.ago
    )
    claim_job!(running_job)

    stub_request(:post, "http://victoria-logs.test:9428/select/logsql/query")
      .to_return(
        status: 200,
        body: {
          "_time" => "2026-04-15T12:00:02Z",
          "_msg" => MultiJson.dump("level" => "info", "message" => "[r3x.run_active_job_id=aj-running-panel] Fresh line")
        }.to_json + "\n"
      )

    get "/workflow-runs/#{running_job.id}/logs"

    assert_response :success
    assert_includes response.body, 'id="run-logs"'
    assert_includes response.body, 'data-r3x-log-refresh="true"'
    assert_includes response.body, "Fresh line"
    refute_includes response.body, "<html"
    refute_includes response.body, "R3x Dashboard"
  end

  test "recent runs keeps run detail shortcut when logs are configured" do
    ENV["R3X_LOGS_PROVIDER"] = "victorialogs"
    ENV["R3X_VICTORIA_LOGS_URL"] = "http://victoria-logs.test:9428"

    get "/workflow-runs"

    assert_response :success
    assert_includes response.body, "View run"
    refute_includes response.body, "logs=1"
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
    assert_equal [ "Trigger", "Status", "Observed", "Run ID", "Details" ], css_select("table").last.css("thead th").map(&:text)
    refute_includes response.body, "<th>Workflow</th>"
    refute_includes response.body, "<th>Queue</th>"
  end

  test "recent runs table uses run id column instead of queue and inline job label" do
    get "/workflow-runs"

    assert_response :success
    assert_equal [ "Workflow", "Status", "Observed", "Trigger", "Run ID", "Details" ], css_select("table").last.css("thead th").map(&:text)
    refute_includes response.body, "<th>Queue</th>"
    refute_includes response.body, "Job <code>"
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

  test "workflow run rerun uses run workflow job for change-detection trigger keys" do
    feed_trigger = "feed:123"
    source_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ feed_trigger, { trigger_payload: { "changed_ids" => [ "a1" ] } } ],
      queue_name: "feed",
      priority: 3,
      finished_at: 10.seconds.ago,
      created_at: 2.minutes.ago,
      updated_at: 10.seconds.ago
    )

    assert_enqueued_jobs 1, only: R3x::RunWorkflowJob do
      post "/workflow-runs/#{source_job.id}/rerun"
    end
    assert_enqueued_jobs 0, only: R3x::ChangeDetectionJob
  end

  private

  def clear_tables
    TestDbCleanup.clear_runtime_tables!
  end

  def claim_job!(job)
    process = SolidQueue::Process.create!(
      kind: "Worker",
      last_heartbeat_at: Time.current,
      pid: Process.pid,
      hostname: "test",
      metadata: "{}",
      name: "test-worker-#{job.id}",
      created_at: Time.current
    )

    SolidQueue::ClaimedExecution.create!(job_id: job.id, process_id: process.id, created_at: 30.seconds.ago)
  end
end

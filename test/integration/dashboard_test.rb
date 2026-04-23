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

  test "root renders overview dashboard" do
    get "/"

    assert_response :success
    assert_includes response.body, "R3x Dashboard"
    assert_includes response.body, "Overview"
    assert_includes response.body, "Needs attention"
    assert_includes response.body, "Recent runs"
    assert_includes response.body, "View failing runs"
    assert_includes response.body, "View all runs"
    assert_includes response.body, "/workflow-runs?status=failed"
    assert_includes response.body, "/workflow-runs"
  end

  test "root overview limits recent runs to 10" do
    11.times do |index|
      created_at = (index + 2).minutes.ago

      create_dashboard_workflow(
        workflow_key: "workflow_#{index}",
        trigger_key: "schedule:#{index}",
        run_status: "finished",
        recorded_at: created_at + 30.seconds
      )
    end

    get "/"

    assert_response :success
    assert_equal 10, css_select(".overview-recent-runs-table tbody tr").size
    refute_includes response.body, "Workflow shortcuts"
  end

  test "root overview recent runs are ordered by observed activity, not enqueue time" do
    clear_tables

    long_running_job = create_dashboard_workflow(
      workflow_key: "slow_workflow",
      trigger_key: "schedule:slow",
      run_status: "finished",
      recorded_at: 5.seconds.ago
    )

    12.times do |index|
      finished_at = (20 - index).minutes.ago

      create_dashboard_workflow(
        workflow_key: "workflow_#{index}",
        trigger_key: "schedule:#{index}",
        run_status: "finished",
        recorded_at: finished_at
      )
    end

    get "/"

    assert_response :success
    first_row_text = css_select(".overview-recent-runs-table tbody tr").first.text
    assert_includes first_row_text, "Slow Workflow"
    assert_includes response.body, "/workflow-runs/#{long_running_job.id}"
    assert_equal 10, css_select(".overview-recent-runs-table tbody tr").size
  end

  test "root overview keeps ten recent visible runs when newer unrelated rows exist" do
    clear_tables

    60.times do |index|
      finished_at = (index + 1).minutes.ago

      DashboardJobRows.create_job!(
        job_class_name: "CleanupJob",
        arguments: [ "tmp/#{index}" ],
        finished_at: finished_at,
        created_at: finished_at - 30.seconds,
        updated_at: finished_at
      )
    end

    10.times do |index|
      finished_at = (90 + index).minutes.ago

      create_dashboard_workflow(
        workflow_key: "visible_workflow_#{index}",
        trigger_key: "schedule:visible:#{index}",
        run_status: "finished",
        recorded_at: finished_at
      )
    end

    get "/"

    assert_response :success
    assert_equal 10, css_select(".overview-recent-runs-table tbody tr").size
    assert_includes response.body, "Visible Workflow 0"
    refute_includes response.body, "CleanupJob"
  end

  test "root overview keeps workflow and failure drill-downs inside needs attention cards" do
    failed_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: 5.minutes.ago,
      updated_at: 30.seconds.ago
    )
    SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "boom", created_at: 30.seconds.ago)

    get "/"

    assert_response :success
    assert_includes response.body, "Open workflow"
    assert_includes response.body, "/workflows/test_workflow"
    assert_includes response.body, "Latest failure"
    assert_includes response.body, "/workflow-runs/#{failed_job.id}"
  end

  test "root overview formats structured failure details instead of dumping raw hash text" do
    failed_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: 5.minutes.ago,
      updated_at: 30.seconds.ago
    )
    SolidQueue::FailedExecution.create!(
      job_id: failed_job.id,
      error: '{"exception_class" => "Faraday::ForbiddenError", "message" => "the server responded with status 403", "backtrace" => ["line one", "line two"]}',
      created_at: 30.seconds.ago
    )

    get "/"

    assert_response :success
    assert_includes response.body, "Faraday::ForbiddenError"
    assert_includes response.body, "the server responded with status 403"
    assert_includes response.body, "Backtrace (2 frames)"
    refute_includes response.body, "&quot;exception_class&quot; =&gt;"
  end

  test "root overview orders needs attention by actual failure time, not later heartbeat time" do
    clear_tables

    create_dashboard_workflow(
      workflow_key: "stale_failure_workflow",
      trigger_key: "schedule:stale",
      run_status: "failed",
      recorded_at: 2.days.ago
    )
    R3x::TriggerState.create!(
      workflow_key: "stale_failure_workflow",
      trigger_key: "schedule:stale",
      trigger_type: "schedule",
      state: {},
      last_checked_at: 1.minute.ago
    )

    create_dashboard_workflow(
      workflow_key: "recent_failure_workflow",
      trigger_key: "schedule:recent",
      run_status: "failed",
      recorded_at: 10.minutes.ago
    )

    get "/"

    assert_response :success
    first_card = css_select(".overview-needs-attention-card").first
    assert_includes first_card.text, "Recent Failure Workflow"
    assert_includes response.body, "Failed "
  end

  test "workflow detail renders trigger state and recent runs" do
    ENV.delete("R3X_LOGS_PROVIDER")

    get "/workflows/test_workflow"

    assert_response :success
    assert_includes response.body, "Overview"
    assert_includes response.body, "View all runs"
    assert_includes response.body, "Last result"
    assert_includes response.body, "Last seen"
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

    get "/workflows"

    assert_response :success
    assert_includes response.body, "Failed"
    assert_includes response.body, "/workflow-runs/#{failed_job.id}"
  end

  test "workflows index renders sortable headers with anchored links" do
    get "/workflows"

    assert_response :success
    assert_includes response.body, 'id="workflows-catalog"'
    assert_includes response.body, 'href="/workflows?direction=asc&amp;sort=workflow#workflows-catalog"'
    assert_includes response.body, 'href="/workflows?direction=desc&amp;sort=health#workflows-catalog"'
    assert_includes response.body, 'href="/workflows?direction=asc&amp;sort=next_trigger#workflows-catalog"'
    assert_includes response.body, 'href="/workflows?direction=desc&amp;sort=last_run#workflows-catalog"'
    assert_includes response.body, 'aria-sort="ascending"'
  end

  test "workflows index toggles the active sort direction on a second click" do
    get "/workflows", params: { sort: "workflow", direction: "asc" }

    assert_response :success
    assert_includes response.body, 'href="/workflows?direction=desc&amp;sort=workflow#workflows-catalog"'
    assert_includes response.body, 'aria-sort="ascending"'

    get "/workflows", params: { sort: "workflow", direction: "desc" }

    assert_response :success
    assert_includes response.body, 'href="/workflows?direction=asc&amp;sort=workflow#workflows-catalog"'
    assert_includes response.body, 'aria-sort="descending"'
  end

  test "workflows index reverses health sort order end to end" do
    clear_tables

    create_dashboard_workflow(workflow_key: "idle_workflow", trigger_key: "schedule:idle")
    create_dashboard_workflow(
      workflow_key: "healthy_workflow",
      trigger_key: "schedule:healthy",
      run_status: "finished",
      recorded_at: 3.minutes.ago
    )
    create_dashboard_workflow(
      workflow_key: "failed_workflow",
      trigger_key: "schedule:failed",
      run_status: "failed",
      recorded_at: 2.minutes.ago
    )
    create_dashboard_workflow(
      workflow_key: "trigger_error_workflow",
      trigger_key: "feed:error",
      trigger_error_at: 1.minute.ago
    )

    get "/workflows", params: { sort: "health", direction: "desc" }

    assert_response :success
    assert_equal(
      [ "Idle Workflow", "Healthy Workflow", "Failed Workflow", "Trigger Error Workflow" ],
      css_select("#workflows-catalog tbody tr .title-link").map { |link| link.text.strip }
    )
    assert_includes response.body, 'href="/workflows?direction=asc&amp;sort=health#workflows-catalog"'
    assert_includes response.body, 'aria-sort="descending"'
  end

  test "root overview shows exact card counts while keeping recent runs capped to 10 rows" do
    51.times do |index|
      running_job = DashboardJobRows.create_job!(
        job_class_name: WORKFLOW_JOB_CLASS_NAME,
        arguments: [ @trigger ],
        active_job_id: "aj-running-#{index}",
        created_at: (index + 1).hours.ago,
        updated_at: (index + 1).hours.ago
      )
      claim_job!(running_job)
    end

    260.times do |index|
      finished_at = (index + 2).minutes.ago

      DashboardJobRows.create_job!(
        job_class_name: WORKFLOW_JOB_CLASS_NAME,
        arguments: [ @trigger ],
        finished_at: finished_at,
        created_at: finished_at - 30.seconds,
        updated_at: finished_at
      )
    end

    get "/"

    assert_response :success

    cards = css_select(".stats .stat-link").index_by { |card| card.at_css(".label").text.strip }

    assert_equal "0", cards.fetch("Needs attention").at_css("strong").text.strip
    assert_equal "51", cards.fetch("Running now").at_css("strong").text.strip
    assert_equal "312", cards.fetch("Recent activity (24h)").at_css("strong").text.strip
    assert_equal 10, css_select(".overview-recent-runs-table tbody tr").size
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
    assert_includes response.body, "Runs"
    assert_includes response.body, "Failed"
    assert_includes response.body, "boom"
    assert_includes response.body, "Open run"
    assert_equal [ "Open run" ], css_select("tbody tr td:last-child a.button.subtle").map { |link| link.text.strip }.uniq
    assert_equal [ "Open run" ], css_select("tbody tr").map { |row| row.css("td").last.text.squish }.uniq
    assert_equal 1, css_select("tbody tr .pill.danger[title='boom']").size
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
    assert_includes response.body, "Failure summary"
    assert_includes response.body, "Full error"
    assert_includes response.body, "Logs"
    assert_includes response.body, "Advanced details"
    assert_includes response.body, "stack line 1"
    assert_includes response.body, "Overview"
    assert_includes response.body, 'class="panel stack panel-spaced"'
    assert_match(/<dt>Finished<\/dt>\s*<dd><time[^>]*>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, response.body)
  end

  test "workflow run detail preserves full long single-line errors" do
    long_error = "API error: " + ("x" * 220)
    failed_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: 5.minutes.ago,
      updated_at: 30.seconds.ago
    )
    SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: long_error, created_at: 30.seconds.ago)

    get "/workflow-runs/#{failed_job.id}"

    assert_response :success
    assert_includes response.body, "Failure summary"
    assert_includes response.body, "Full error"
    assert_includes response.body, long_error
  end

  test "workflow run detail hides failure details when run succeeded" do
    get "/workflow-runs/#{@job.id}"

    assert_response :success
    refute_includes response.body, "Failure summary"
    refute_includes response.body, "Full error"
  end

  test "workflow run detail shows absolute metadata timestamps" do
    get "/workflow-runs/#{@job.id}"

    assert_response :success
    assert_includes response.body, "Summary"
    assert_includes response.body, "Duration"
    assert_match(/<span class="label">Duration<\/span>\s*<strong>\d{2}:\d{2}:\d{2}<\/strong>/, response.body)
    refute_includes response.body, "<span class=\"label\">Result</span>"
    assert_match(/<dt>Enqueued<\/dt>\s*<dd><time[^>]*>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, response.body)
    refute_match(/<dt>Enqueued<\/dt>\s*<dd><time[^>]*>about /, response.body)
    assert_match(/<dt>Finished<\/dt>\s*<dd><time[^>]*>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, response.body)
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
    refute_match(/<dt>Finished<\/dt>/, response.body)
  end

  test "workflow run detail shows scheduled timestamp only in advanced details" do
    scheduled_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ @trigger ],
      created_at: Time.zone.parse("2026-04-23 10:00:00 UTC"),
      updated_at: Time.zone.parse("2026-04-23 10:05:15 UTC"),
      finished_at: Time.zone.parse("2026-04-23 10:05:15 UTC"),
      scheduled_at: Time.zone.parse("2026-04-23 10:00:00 UTC")
    )

    get "/workflow-runs/#{scheduled_job.id}"

    assert_response :success
    refute_match(/<span class="label">Scheduled<\/span>/, response.body)
    assert_match(/<dt>Scheduled<\/dt>\s*<dd><time[^>]*>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/, response.body)
  end

  test "workflow run detail does not show rerun action" do
    get "/workflow-runs/#{@job.id}"

    assert_response :success
    refute_includes response.body, "Rerun"
    refute_includes response.body, "/workflow-runs/#{@job.id}/rerun"
  end

  test "workflow run rerun route no longer exists" do
    post "/workflow-runs/#{@job.id}/rerun"

    assert_response :not_found
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
    assert_includes response.body, "Logs"
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
    assert_includes response.body, "Open run"
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
    assert_equal [ "Result", "Observed", "Trigger", "Open" ], css_select("table").last.css("thead th").map(&:text)
    refute_includes response.body, "<th>Workflow</th>"
    refute_includes response.body, "<th>Queue</th>"
  end

  test "recent runs table uses run id column instead of queue and inline job label" do
    get "/workflow-runs"

    assert_response :success
    assert_equal [ "Workflow", "Result", "Observed", "Trigger", "Run ID", "Open" ], css_select("table").last.css("thead th").map(&:text)
    refute_includes response.body, "<th>Queue</th>"
    refute_includes response.body, WORKFLOW_JOB_CLASS_NAME
  end

  test "ops jobs route stays available" do
    get "/ops/jobs"

    assert_response :success
  end

  test "workflow detail can enqueue run now from recurring task" do
    assert_difference -> { SolidQueue::Job.where(class_name: WORKFLOW_JOB_CLASS_NAME).count }, 1 do
      post "/workflows/test_workflow/run_trigger"
    end

    assert_redirected_to "/workflows/test_workflow"
    job = SolidQueue::Job.order(:id).last
    assert_equal [], Dashboard::Run.find(job.id).workflow_arguments
  end

  test "workflow index shows run now for manual-only workflows discovered from direct runs" do
    clear_tables
    DashboardJobRows.create_job!(
      job_class_name: "Workflows::ManualOnlyWorkflow",
      arguments: [],
      finished_at: 1.minute.ago,
      created_at: 2.minutes.ago,
      updated_at: 1.minute.ago
    )

    get "/workflows"

    assert_response :success
    assert_includes response.body, "Manual Only Workflow"
    assert_includes response.body, "/workflows/manual_only_workflow/run_trigger"
    refute_includes response.body, "Unavailable"
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

  test "workflow detail shows generic run now for change-detecting-only workflows" do
    clear_tables
    SolidQueue::RecurringTask.create!(
      key: "workflow:feed_watch:feed:123",
      schedule: "*/5 * * * *",
      class_name: "R3x::ChangeDetectionJob",
      arguments: [ "feed_watch", { "trigger_key" => "feed:123" } ],
      queue_name: "feed",
      static: false
    )

    get "/workflows/feed_watch"

    assert_response :success
    assert_includes response.body, "Run now"
  end

  test "workflow detail run now enqueues a manual workflow job for change-detecting-only workflows" do
    clear_tables
    SolidQueue::RecurringTask.create!(
      key: "workflow:feed_watch:feed:123",
      schedule: "*/5 * * * *",
      class_name: "R3x::ChangeDetectionJob",
      arguments: [ "feed_watch", { "trigger_key" => "feed:123" } ],
      queue_name: "feed",
      priority: 4,
      static: false
    )

    post "/workflows/feed_watch/run_trigger"

    assert_redirected_to "/workflows/feed_watch"

    job = SolidQueue::Job.order(:id).last
    assert_equal "Workflows::FeedWatch", job.class_name
    assert_equal "feed", job.queue_name
    assert_equal 4, job.priority
    assert_equal [], Dashboard::Run.find(job.id).workflow_arguments
  end

  test "workflow detail run now returns not found for unknown workflow keys" do
    clear_tables

    post "/workflows/missing_workflow/run_trigger"

    assert_response :not_found
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

  def create_dashboard_workflow(workflow_key:, trigger_key:, run_status: nil, recorded_at: nil, trigger_error_at: nil)
    job_class_name = ensure_dashboard_job_class("#{workflow_key.camelize}Job").name

    SolidQueue::RecurringTask.create!(
      key: "workflow:#{workflow_key}:#{trigger_key}",
      schedule: "0 * * * *",
      class_name: job_class_name,
      arguments: [ trigger_key ],
      queue_name: "default",
      static: false
    )

    if trigger_error_at.present?
      R3x::TriggerState.create!(
        workflow_key: workflow_key,
        trigger_key: trigger_key,
        trigger_type: "feed",
        state: {},
        last_error_at: trigger_error_at,
        last_error_message: "#{workflow_key} error"
      )
    end

    return if run_status.blank?

    job = DashboardJobRows.create_job!(
      job_class_name: job_class_name,
      arguments: [ trigger_key ],
      finished_at: run_status == "finished" ? recorded_at : nil,
      created_at: recorded_at - 1.minute,
      updated_at: recorded_at
    )

    return job unless run_status == "failed"

    SolidQueue::FailedExecution.create!(job_id: job.id, error: "#{workflow_key} failed", created_at: recorded_at)
    job
  end

  def ensure_dashboard_job_class(name)
    test_jobs = if Object.const_defined?(:TestDashboardJobs, false)
      Object.const_get(:TestDashboardJobs)
    else
      Object.const_set(:TestDashboardJobs, Module.new)
    end

    return test_jobs.const_get(name, false) if test_jobs.const_defined?(name, false)

    test_jobs.const_set(name, Class.new(R3x::TestSupport::DashboardWorkflowJob))
  end
end

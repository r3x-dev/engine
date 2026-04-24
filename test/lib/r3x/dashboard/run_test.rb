require "test_helper"

class Dashboard::RunTest < ActiveSupport::TestCase
  WORKFLOW_JOB_CLASS_NAME = DashboardTestWorkflows.ensure_class("TestWorkflow").freeze

  setup do
    TestDbCleanup.clear_runtime_tables!
  end

  teardown do
    TestDbCleanup.clear_runtime_tables!
  end

  test "status and recorded_at resolve across dashboard-visible execution states" do
    failed_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ "schedule:failed" ],
      created_at: 10.minutes.ago,
      updated_at: 9.minutes.ago
    )
    failed_at = 8.minutes.ago
    SolidQueue::FailedExecution.create!(job_id: failed_job.id, error: "boom", created_at: failed_at)

    finished_at = 7.minutes.ago
    finished_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ "schedule:finished" ],
      finished_at: finished_at,
      created_at: 9.minutes.ago,
      updated_at: finished_at
    )

    running_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ "schedule:running" ],
      created_at: 8.minutes.ago,
      updated_at: 7.minutes.ago
    )
    running_at = 6.minutes.ago
    claim_job!(running_job, claimed_at: running_at)

    queued_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ "schedule:queued" ],
      created_at: 7.minutes.ago,
      updated_at: 7.minutes.ago
    )
    queued_at = 5.minutes.ago
    SolidQueue::ReadyExecution.find_by!(job_id: queued_job.id).update!(created_at: queued_at)

    blocked_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ "schedule:blocked" ],
      concurrency_key: "demo-key",
      created_at: 6.minutes.ago,
      updated_at: 6.minutes.ago
    )
    SolidQueue::ReadyExecution.find_by!(job_id: blocked_job.id).destroy!
    blocked_at = 4.minutes.ago
    SolidQueue::BlockedExecution.create!(job_id: blocked_job.id, queue_name: "default", priority: 0, concurrency_key: "demo-key", expires_at: 1.hour.from_now, created_at: blocked_at)

    scheduled_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ "schedule:scheduled" ],
      created_at: 5.minutes.ago,
      updated_at: 5.minutes.ago,
      scheduled_at: 3.minutes.ago
    )
    scheduled_at = 2.minutes.ago
    SolidQueue::ScheduledExecution.create!(
      job_id: scheduled_job.id,
      queue_name: scheduled_job.queue_name,
      priority: scheduled_job.priority,
      scheduled_at: scheduled_at,
      created_at: 5.minutes.ago
    )

    fallback_queued_job = DashboardJobRows.create_job!(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ "schedule:fallback" ],
      created_at: 4.minutes.ago,
      updated_at: 4.minutes.ago
    )
    SolidQueue::ReadyExecution.find_by!(job_id: fallback_queued_job.id).destroy!

    runs = Dashboard::Run.where(id: [
      failed_job.id,
      finished_job.id,
      running_job.id,
      queued_job.id,
      blocked_job.id,
      scheduled_job.id,
      fallback_queued_job.id
    ]).with_execution_associations.index_by(&:id)

    assert_equal "failed", runs.fetch(failed_job.id).status
    assert_equal failed_at.to_i, runs.fetch(failed_job.id).recorded_at.to_i

    assert_equal "finished", runs.fetch(finished_job.id).status
    assert_equal finished_at.to_i, runs.fetch(finished_job.id).recorded_at.to_i

    assert_equal "running", runs.fetch(running_job.id).status
    assert_equal running_at.to_i, runs.fetch(running_job.id).recorded_at.to_i

    assert_equal "queued", runs.fetch(queued_job.id).status
    assert_equal queued_at.to_i, runs.fetch(queued_job.id).recorded_at.to_i

    assert_equal "blocked", runs.fetch(blocked_job.id).status
    assert_equal blocked_at.to_i, runs.fetch(blocked_job.id).recorded_at.to_i

    assert_equal "scheduled", runs.fetch(scheduled_job.id).status
    assert_equal scheduled_job.scheduled_at.to_i, runs.fetch(scheduled_job.id).recorded_at.to_i

    assert_equal "queued", runs.fetch(fallback_queued_job.id).status
    assert_equal fallback_queued_job.created_at.to_i, runs.fetch(fallback_queued_job.id).recorded_at.to_i
  end

  test "workflow payload helpers parse serialized workflow arguments" do
    raw_arguments = DashboardJobRows.serialized_job_payload(
      job_class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ "schedule:abc123", { trigger_payload: { "id" => "42" } } ]
    )
    run = Dashboard::Run.new(arguments: raw_arguments)

    assert_equal [ "schedule:abc123", { trigger_payload: { "id" => "42" } } ], run.workflow_arguments
    assert_equal "schedule:abc123", run.trigger_key
    assert_equal({ "id" => "42" }, run.trigger_payload)
  end

  test "normalize_arguments symbolized marked keyword hashes" do
    normalized = Dashboard::Run.normalize_arguments(
      "arguments" => [
        "schedule:abc123",
        {
          "trigger_payload" => { "id" => "99", "_aj_symbol_keys" => [] },
          "_aj_ruby2_keywords" => [ "trigger_payload" ]
        }
      ]
    )

    assert_equal(
      {
        "arguments" => [ "schedule:abc123", { trigger_payload: { "id" => "99" } } ]
      },
      normalized
    )
  end

  test "enqueue_direct! persists a direct workflow row with active job payload" do
    job = Dashboard::Run.enqueue_direct!(
      class_name: WORKFLOW_JOB_CLASS_NAME,
      arguments: [ "schedule:abc123", { trigger_payload: { "id" => "42" } } ],
      queue_name: "critical",
      priority: 7
    )

    assert_equal WORKFLOW_JOB_CLASS_NAME, job.class_name
    assert_equal "critical", job.queue_name
    assert_equal 7, job.priority
    assert_equal [ "schedule:abc123", { trigger_payload: { "id" => "42" } } ], job.workflow_arguments
    assert SolidQueue::ReadyExecution.exists?(job_id: job.id)
  end

  test "enqueue_direct! maps framework enqueue errors to dashboard error" do
    output = capture_logged_output do
      error = assert_raises(Dashboard::Run::EnqueueError) do
        SolidQueue::Job.singleton_class.alias_method :__dashboard_run_test_original_enqueue, :enqueue
        SolidQueue::Job.singleton_class.define_method(:enqueue) do |_active_job|
          raise SolidQueue::Job::EnqueueError, "boom"
        end

        begin
          Dashboard::Run.enqueue_direct!(
            class_name: WORKFLOW_JOB_CLASS_NAME,
            arguments: [ "schedule:abc123" ],
            queue_name: "critical",
            priority: 7
          )
        ensure
          SolidQueue::Job.singleton_class.alias_method :enqueue, :__dashboard_run_test_original_enqueue
          SolidQueue::Job.singleton_class.remove_method :__dashboard_run_test_original_enqueue
        end
      end

      assert_includes error.message, "Direct workflow enqueue failed"
    end

      assert_includes output, "Dashboard direct enqueue failed"
      assert_includes output, "error_class=SolidQueue::Job::EnqueueError"
  end

  private
    def claim_job!(job, claimed_at:)
      process = SolidQueue::Process.create!(
        kind: "Worker",
        last_heartbeat_at: Time.current,
        pid: Process.pid,
        hostname: "test",
        metadata: "{}",
        name: "test-worker-#{job.id}",
        created_at: Time.current
      )

      SolidQueue::ClaimedExecution.create!(job_id: job.id, process_id: process.id, created_at: claimed_at)
    end
end

# frozen_string_literal: true

require "test_helper"
require_relative "../../../fixtures/workflows/admission_workflow/workflow"

class R3x::Workflow::EnqueueJobTest < ActiveSupport::TestCase
  setup do
    TestDbCleanup.clear_runtime_tables!
    SolidQueue::Semaphore.delete_all
    @original_adapter = Workflows::AdmissionWorkflow.queue_adapter
    Workflows::AdmissionWorkflow.queue_adapter = :solid_queue
    @original_workflows = R3x::Workflow::Registry.all
    R3x::Workflow::Registry.register(Workflows::AdmissionWorkflow)
    @worker = SolidQueue::Process.create!(kind: "Worker", name: "admission-test", pid: Process.pid, hostname: "test", last_heartbeat_at: Time.current)
  end

  teardown do
    Workflows::AdmissionWorkflow.queue_adapter = @original_adapter
    R3x::Workflow::Registry.reset!
    @original_workflows.each { |workflow| R3x::Workflow::Registry.register(workflow) }
    TestDbCleanup.clear_runtime_tables!
    SolidQueue::Semaphore.delete_all
  end

  test "each request identifies its workflow before admission and across continuation" do
    requests = 2.times.map { enqueue_request(["manual:manual"]) }
    workflow_job_ids = requests.map(&:workflow_job_id)

    assert_equal 2, workflow_job_ids.uniq.size
    assert_empty workflow_job_ids & requests.map(&:active_job_id)
    assert_nil requests.first.workflow_run

    2.times { perform_next }

    assert_equal workflow_job_ids, workflow_jobs.pluck(:active_job_id)
    assert_equal workflow_jobs.pluck(:id), requests.map { |request| request.workflow_run.id }

    perform_next

    continuation = workflow_jobs.last

    assert_equal workflow_job_ids.first, continuation.active_job_id
    assert_equal workflow_job_ids.first, requests.first.reload.workflow_job_id
  end

  test "dashboard requests use the real class key and group and release blocked work after continuation" do
    requests = 2.times.map { enqueue_request(["manual:manual", { trigger_payload: { "partition" => "same" } }]) }

    2.times { perform_next }

    runs = workflow_jobs.to_a

    assert_equal 2, runs.size
    assert_equal ["admission/Workflows::AdmissionWorkflow/same"], runs.map(&:concurrency_key).uniq
    assert_equal %i[ready blocked], runs.map(&:status)
    assert_equal [true, true], requests.map { |request| request.reload.finished_at.present? }
    assert_equal ["manual:manual", { trigger_payload: { "partition" => "same" } }], Dashboard::Run.find(runs.first.id).workflow_arguments

    perform_next

    assert_equal :ready, runs.last.reload.status
    continuation = workflow_jobs.order(:id).last

    assert_equal :scheduled, continuation.status
    assert_equal runs.first.active_job_id, continuation.active_job_id
    assert_equal runs.first.concurrency_key, continuation.concurrency_key

    travel 2.minutes do
      SolidQueue::ScheduledExecution.dispatch_next_batch(10)

      assert_equal :blocked, continuation.reload.status

      perform_next

      assert_equal :ready, continuation.reload.status
      perform_next

      assert_predicate continuation.reload, :finished?
      assert_empty SolidQueue::FailedExecution.all
    end
  end

  test "scheduler and dashboard jobs share the same admission limit" do
    task = SolidQueue::RecurringTask.create!(key: "workflow:admission_workflow:scheduled", class_name: Workflows::AdmissionWorkflow.name,
      arguments: ["schedule:scheduled"], schedule: "0 * * * *", static: false)
    task.enqueue(at: Time.current)
    enqueue_request(["manual:manual"])

    # Claim the request before the older workflow so admission observes its slot.
    request_job = SolidQueue::Job.where(class_name: R3x::Workflow::EnqueueJob.name).sole
    SolidQueue::ClaimedExecution.claiming([request_job.id], @worker.id) do
      SolidQueue::ReadyExecution.where(job_id: request_job.id).delete_all
    end.sole.perform

    assert_equal %i[ready blocked], workflow_jobs.map(&:status)
    assert_equal 1, workflow_jobs.distinct.count(:concurrency_key)
  end

  test "queued retries reacquire the slot and release the next blocked job" do
    enqueue_request(["manual:retry"])
    perform_next
    first = workflow_jobs.sole
    perform_next
    retry_job = workflow_jobs.order(:id).last

    assert_predicate first.reload, :finished?
    assert_equal :scheduled, retry_job.status
    assert_equal first.active_job_id, retry_job.active_job_id
    assert_equal first.concurrency_key, retry_job.concurrency_key

    Workflows::AdmissionWorkflow.perform_later("manual:manual")

    travel 2.minutes do
      SolidQueue::ScheduledExecution.dispatch_next_batch(10)

      assert_equal :blocked, retry_job.reload.status

      perform_next

      assert_equal :ready, retry_job.reload.status
      perform_next

      assert_predicate retry_job.reload, :finished?
      assert_empty SolidQueue::FailedExecution.all
    end
  end

  test "failed class resolution remains a failed admission request without a workflow run" do
    request = enqueue_request([], class_name: "Workflows::NotMounted")

    assert_raises(NameError) { perform_next }

    assert_equal "failed", request.reload.status
    assert_empty workflow_jobs
    assert_equal 1, SolidQueue::Job.count
  end

  test "a real enqueue callback abort is visible as an admission failure" do
    request = enqueue_request(["abort"])

    error = assert_raises(RuntimeError) { perform_next }

    assert_includes error.message, "aborted or discarded"
    assert_equal "failed", request.reload.status
    assert_empty workflow_jobs
  end

  test "discarded concurrency conflicts remain visible as failed requests" do
    Workflows::AdmissionWorkflow.concurrency_on_conflict = :discard
    enqueue_request(["manual:manual"])
    rejected_request = enqueue_request(["manual:manual"])
    perform_next

    error = assert_raises(RuntimeError) { perform_next }

    assert_includes error.message, "aborted or discarded"
    assert_equal "failed", rejected_request.reload.status
    assert_equal 1, workflow_jobs.count
  ensure
    Workflows::AdmissionWorkflow.concurrency_on_conflict = :block
  end

  private

  def enqueue_request(arguments, class_name: Workflows::AdmissionWorkflow.name)
    Dashboard::DirectWorkflowEnqueuer.enqueue!(class_name:, arguments:, queue_name: "default", priority: 0)
  end

  def perform_next
    SolidQueue::ReadyExecution.claim(["*"], 1, @worker.id).sole.perform
  end

  def workflow_jobs
    SolidQueue::Job.where(class_name: Workflows::AdmissionWorkflow.name).order(:id)
  end
end

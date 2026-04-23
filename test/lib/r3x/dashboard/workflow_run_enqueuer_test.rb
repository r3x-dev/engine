require "test_helper"

module R3x
  module Dashboard
    class WorkflowRunEnqueuerTest < ActiveSupport::TestCase
      WORKFLOW_JOB_CLASS_NAME = R3x::TestSupport::DashboardWorkflowJob.name.freeze

      include ActiveJob::TestHelper

      setup do
        TestDbCleanup.clear_runtime_tables!
        clear_enqueued_jobs
      end

      teardown do
        clear_enqueued_jobs
        TestDbCleanup.clear_runtime_tables!
      end

      test "enqueue without trigger key uses the persisted direct recurring target with manual arguments" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:schedule:123",
          schedule: "0 * * * *",
          class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:123" ],
          queue_name: "critical",
          priority: 7,
          static: false
        )

        assert_difference -> { SolidQueue::Job.where(class_name: WORKFLOW_JOB_CLASS_NAME).count }, 1 do
          Workflow::RunEnqueuer.new(workflow_key: "test_workflow", trigger_key: nil).enqueue!
        end

        job = SolidQueue::Job.order(:id).last
        assert_equal "critical", job.queue_name
        assert_equal 7, job.priority
        assert_equal [], ::Dashboard::Run.find(job.id).workflow_arguments
      end

      test "enqueue without trigger key prefers current recurring task metadata over the last run" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:schedule:123",
          schedule: "0 * * * *",
          class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:123" ],
          queue_name: "critical",
          priority: 7,
          static: false
        )
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:123" ],
          queue_name: "old_queue",
          priority: 2,
          finished_at: 30.seconds.ago,
          created_at: 2.minutes.ago,
          updated_at: 30.seconds.ago
        )

        assert_difference -> { SolidQueue::Job.where(class_name: WORKFLOW_JOB_CLASS_NAME).count }, 1 do
          Workflow::RunEnqueuer.new(workflow_key: "test_workflow", trigger_key: nil).enqueue!
        end

        job = SolidQueue::Job.order(:id).last
        assert_equal "critical", job.queue_name
        assert_equal 7, job.priority
      end

      test "enqueue without trigger key falls back to the last visible direct workflow run metadata only" do
        R3x::TriggerState.create!(
          workflow_key: "test_workflow",
          trigger_key: "feed:123",
          trigger_type: "feed",
          state: {},
          last_checked_at: 1.minute.ago
        )
        DashboardJobRows.create_job!(
          job_class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "feed:123", { trigger_payload: { "id" => "42" } } ],
          queue_name: "feeds",
          priority: 3,
          finished_at: 30.seconds.ago,
          created_at: 2.minutes.ago,
          updated_at: 30.seconds.ago
        )

        assert_difference -> { SolidQueue::Job.where(class_name: WORKFLOW_JOB_CLASS_NAME).count }, 1 do
          Workflow::RunEnqueuer.new(workflow_key: "test_workflow", trigger_key: nil).enqueue!
        end

        job = SolidQueue::Job.order(:id).last
        assert_equal "feeds", job.queue_name
        assert_equal 3, job.priority
        assert_equal [], ::Dashboard::Run.find(job.id).workflow_arguments
      end

      test "enqueue without trigger key derives workflow class for change-detecting-only workflows" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:feed_watch:feed:123",
          schedule: "*/5 * * * *",
          class_name: "R3x::ChangeDetectionJob",
          arguments: [ "feed_watch", { "trigger_key" => "feed:123" } ],
          queue_name: "feeds",
          priority: 3,
          static: false
        )

        assert_difference -> { SolidQueue::Job.where(class_name: "Workflows::FeedWatch").count }, 1 do
          Workflow::RunEnqueuer.new(workflow_key: "feed_watch", trigger_key: nil).enqueue!
        end

        job = SolidQueue::Job.order(:id).last
        assert_equal "Workflows::FeedWatch", job.class_name
        assert_equal "feeds", job.queue_name
        assert_equal 3, job.priority
        assert_equal [], ::Dashboard::Run.find(job.id).workflow_arguments
      end

      test "enqueue without trigger key matches recurring tasks for workflow key literally" do
        ensure_workflow_job_class("FooBar")
        ensure_workflow_job_class("Foo1bar")

        SolidQueue::RecurringTask.create!(
          key: "workflow:foo_bar:schedule:1",
          schedule: "0 * * * *",
          class_name: "Workflows::FooBar",
          arguments: [ "schedule:1" ],
          queue_name: "expected",
          priority: 7,
          static: false
        )
        SolidQueue::RecurringTask.create!(
          key: "workflow:foo1bar:schedule:1",
          schedule: "0 * * * *",
          class_name: "Workflows::Foo1bar",
          arguments: [ "schedule:1" ],
          queue_name: "wrong",
          priority: 1,
          static: false
        )

        assert_difference -> { SolidQueue::Job.where(class_name: "Workflows::FooBar").count }, 1 do
          Workflow::RunEnqueuer.new(workflow_key: "foo_bar", trigger_key: nil).enqueue!
        end

        job = SolidQueue::Job.order(:id).last
        assert_equal "Workflows::FooBar", job.class_name
        assert_equal "expected", job.queue_name
        assert_equal 7, job.priority
      end

      test "enqueue with recurring workflow trigger uses direct workflow class and queue metadata" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:schedule:123",
          schedule: "0 * * * *",
          class_name: WORKFLOW_JOB_CLASS_NAME,
          arguments: [ "schedule:123" ],
          queue_name: "critical",
          priority: 7,
          static: false
        )

        assert_difference -> { SolidQueue::Job.where(class_name: WORKFLOW_JOB_CLASS_NAME).count }, 1 do
          Workflow::RunEnqueuer.new(workflow_key: "test_workflow", trigger_key: "schedule:123").enqueue!
        end

        job = SolidQueue::Job.order(:id).last
        assert_equal "critical", job.queue_name
        assert_equal 7, job.priority
        assert_equal [ "schedule:123" ], ::Dashboard::Run.find(job.id).workflow_arguments
      end

      test "enqueue with change-detection task uses change detection job" do
        SolidQueue::RecurringTask.create!(
          key: "workflow:test_workflow:feed:123",
          schedule: "*/5 * * * *",
          class_name: "R3x::ChangeDetectionJob",
          arguments: [ "test_workflow", { "trigger_key" => "feed:123" } ],
          queue_name: "feeds",
          priority: 3,
          static: false
        )

        assert_enqueued_with(
          job: R3x::ChangeDetectionJob,
          args: [ "test_workflow", { trigger_key: "feed:123" } ],
          queue: "feeds",
          priority: 3
        ) do
          Workflow::RunEnqueuer.new(workflow_key: "test_workflow", trigger_key: "feed:123").enqueue!
        end
      end

      test "enqueue without direct target raises a key error" do
        assert_raises(KeyError) do
          Workflow::RunEnqueuer.new(workflow_key: "missing_workflow", trigger_key: nil).enqueue!
        end
      end

      test "enqueue with unknown trigger key raises from recurring task lookup" do
        assert_raises(ActiveRecord::RecordNotFound) do
          Workflow::RunEnqueuer.new(workflow_key: "test_workflow", trigger_key: "missing:123").enqueue!
        end
      end

      private
        def ensure_workflow_job_class(name)
          workflows = if Object.const_defined?(:Workflows, false)
            Object.const_get(:Workflows)
          else
            Object.const_set(:Workflows, Module.new)
          end

          return workflows.const_get(name, false) if workflows.const_defined?(name, false)

          workflows.const_set(name, Class.new(R3x::TestSupport::DashboardWorkflowJob))
        end
    end
  end
end

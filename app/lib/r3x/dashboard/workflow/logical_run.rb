# frozen_string_literal: true

module R3x
  module Dashboard
    module Workflow
      class LogicalRun
        def initialize(jobs:, workflow_key:, recurring_task: nil, known_workflow: true)
          @jobs = jobs.sort_by(&:created_at)
          @workflow_key = workflow_key
          @recurring_task = recurring_task
          @known_workflow = known_workflow
        end

        def to_h
          summary.merge(
            active_job_id: first_job.active_job_id,
            enqueued_at: first_job.created_at,
            finished_at: (status == "finished") ? last_job.finished_at : nil,
            known_workflow:,
            mission_control_path: "/ops/jobs",
            scheduled_at: last_job.scheduled_execution&.scheduled_at || last_job.scheduled_at,
            started_at: first_job.claimed_execution&.created_at || first_job.created_at,
            trigger_key:,
            trigger_payload: first_job.trigger_payload,
            trigger_schedule: recurring_task&.schedule,
            workflow_title: workflow_key.titleize,
          )
        end

        def summary
          {
            class_name: first_job.class_name,
            error: last_job.failed_execution&.error,
            job_id: last_job.id,
            priority: last_job.priority,
            queue_name: last_job.queue_name,
            recorded_at: last_job.recorded_at,
            resumptions: last_job.observed_resumptions,
            status:,
            workflow_key:,
          }
        end

        private

        attr_reader :jobs, :known_workflow, :recurring_task, :workflow_key

        def first_job
          jobs.first
        end

        def last_job
          jobs.last
        end

        def status
          @status ||= ::Dashboard::Run.logical_status(jobs.map(&:status), resumptions: last_job.resumptions)
        end

        def trigger_key
          first_job.trigger_key
        end
      end
    end
  end
end

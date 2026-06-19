# frozen_string_literal: true

module R3x
  module Dashboard
    module Workflow
      class Runs
        DEFAULT_LIMIT = 50

        def self.statuses
          ::Dashboard::Run::STATUSES
        end

        def initialize(workflow_key: nil, status: nil, limit: DEFAULT_LIMIT, job_ids: nil)
          @job_ids = Array(job_ids).presence
          @workflow_key = workflow_key.presence
          @status = status.presence&.to_s
          @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
        end

        def all
          runs = logical_job_groups.filter_map { |job_group| build_logical_run(job_group) }
          runs.select! { |run| run[:workflow_key] == workflow_key } if workflow_key.present?
          runs.select! { |run| run[:status] == status } if status.present?
          runs.sort_by { |run| run[:recorded_at] || run[:enqueued_at] || Time.zone.at(0) }.reverse.first(limit)
        end

        def find!(job_id)
          initial_job = find_job!(job_id)
          @jobs = ([initial_job] + related_jobs_for(initial_job)).uniq(&:id)

          build_logical_run(@jobs) || raise(KeyError, "Unknown workflow run '#{job_id}'")
        rescue ActiveRecord::RecordNotFound
          raise KeyError, "Unknown workflow run '#{job_id}'"
        end

        private

        attr_reader :job_ids, :limit, :status, :workflow_key

        def logical_job_groups
          jobs_with_related_fragments
            .group_by { |job| job.active_job_id.presence || job.id }
            .values
        end

        def jobs_with_related_fragments
          (jobs + related_jobs_for(jobs)).uniq(&:id)
        end

        def related_jobs_for(records)
          active_job_ids = Array(records).map(&:active_job_id).compact_blank.uniq
          return [] if active_job_ids.empty?

          ::Dashboard::Run.with_execution_associations.where(active_job_id: active_job_ids).to_a
        end

        def build_logical_run(job_group)
          sorted_jobs = job_group.sort_by(&:created_at)
          first_job = sorted_jobs.first
          last_job = sorted_jobs.last
          resolved_workflow_key = class_names_to_keys[first_job.class_name]
          return if resolved_workflow_key.blank?

          trigger_key = first_job.trigger_key
          recurring_task = recurring_task_for(workflow_key: resolved_workflow_key, trigger_key:)
          statuses = sorted_jobs.map(&:status)
          status = ::Dashboard::Run.logical_status(statuses, resumptions: last_job.resumptions)

          {
            active_job_id: first_job.active_job_id,
            class_name: first_job.class_name,
            enqueued_at: first_job.created_at,
            error: last_job.failed_execution&.error,
            finished_at: (status == "finished") ? last_job.finished_at : nil,
            job_id: last_job.id,
            known_workflow: class_names_to_keys.key?(first_job.class_name),
            mission_control_path: "/ops/jobs",
            priority: last_job.priority,
            queue_name: last_job.queue_name,
            recorded_at: last_job.recorded_at,
            resumptions: last_job.observed_resumptions,
            scheduled_at: last_job.scheduled_execution&.scheduled_at || last_job.scheduled_at,
            started_at: first_job.claimed_execution&.created_at || first_job.created_at,
            status:,
            trigger_key:,
            trigger_payload: first_job.trigger_payload,
            trigger_schedule: recurring_task&.schedule,
            workflow_key: resolved_workflow_key,
            workflow_title: resolved_workflow_key.titleize
          }
        end

        def find_job!(job_id)
          ::Dashboard::Run.with_execution_associations.find(job_id)
        end

        def jobs
          @jobs ||= begin
            scope = jobs_scope
            scope = scope.where(id: job_ids) if job_ids.present?
            scope = scope.order(created_at: :desc).limit(query_limit) unless job_ids.present?
            scope.to_a
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            []
          end
        end

        def recurring_task_for(workflow_key:, trigger_key:)
          return if trigger_key.blank?

          recurring_tasks_by_workflow_and_trigger_key.dig(workflow_key, trigger_key)
        end

        def recurring_tasks_by_workflow_and_trigger_key
          @recurring_tasks_by_workflow_and_trigger_key ||= begin
            ::Dashboard::RecurringTask
              .workflow_tasks
              .to_a
              .each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |task, mapping|
                mapping[task.workflow_key][task.trigger_key] ||= task
              end
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            {}
          end
        end

        def catalog
          @catalog ||= Workflow::Catalog.new
        end

        def class_names_to_keys
          @class_names_to_keys ||= catalog.class_names_to_keys
        end

        def jobs_scope
          scope = ::Dashboard::Run.with_execution_associations.dashboard_visible(relevant_class_names)

          return scope if status.blank?

          scope.for_status(status)
        end

        def relevant_class_names
          workflow_key.present? ? catalog.class_names_for(workflow_key) : class_names_to_keys.keys
        end

        def query_limit
          return nil if job_ids.present?
          return limit unless workflow_key.present? || status.present?

          [limit * 10, DEFAULT_LIMIT].max
        end
      end
    end
  end
end

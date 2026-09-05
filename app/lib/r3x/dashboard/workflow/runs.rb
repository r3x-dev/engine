# frozen_string_literal: true

module R3x
  module Dashboard
    module Workflow
      class Runs
        DEFAULT_LIMIT = 50

        def self.statuses
          ::Dashboard::Run::STATUSES
        end

        def initialize(workflow_key: nil, status: nil, limit: DEFAULT_LIMIT)
          @workflow_key = workflow_key.presence
          @status = status.presence&.to_s
          @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
        end

        def all
          logical_job_groups.filter_map { |job_group| build_logical_run(job_group) }
        end

        def find!(job_id)
          initial_job = find_job!(job_id)
          @jobs = ([initial_job] + related_jobs_for(initial_job)).uniq(&:id)

          build_logical_run(@jobs) || raise(KeyError, "Unknown workflow run '#{job_id}'")
        rescue ActiveRecord::RecordNotFound
          raise KeyError, "Unknown workflow run '#{job_id}'"
        end

        private

        attr_reader :limit, :status, :workflow_key

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
          sorted_jobs = job_group.sort_by { |job| [job.created_at, job.id] }
          first_job = sorted_jobs.first
          resolved_workflow_key = class_names_to_keys[first_job.class_name]
          return if resolved_workflow_key.blank?

          trigger_key = first_job.trigger_key
          recurring_task = recurring_task_for(workflow_key: resolved_workflow_key, trigger_key:)
          Workflow::LogicalRun.new(
            jobs: sorted_jobs,
            workflow_key: resolved_workflow_key,
            recurring_task:,
            known_workflow: true,
          ).to_h
        end

        def find_job!(job_id)
          ::Dashboard::Run.with_execution_associations.find(job_id)
        end

        def jobs
          @jobs ||= begin
            ids = ::Dashboard::Run.recent_ids(limit:, class_names: relevant_class_names, status:)
            ::Dashboard::Run.with_execution_associations.in_order_of(:id, ids).to_a
          end
        end

        def recurring_task_for(workflow_key:, trigger_key:)
          return if trigger_key.blank?

          recurring_tasks_by_workflow_and_trigger_key.dig(workflow_key, trigger_key)
        end

        def recurring_tasks_by_workflow_and_trigger_key
          @recurring_tasks_by_workflow_and_trigger_key ||= ::Dashboard::RecurringTask
            .workflow_tasks
            .to_a
            .each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |task, mapping|
              mapping[task.workflow_key][task.trigger_key] ||= task
            end
        end

        def catalog
          @catalog ||= Workflow::Catalog.new
        end

        def class_names_to_keys
          @class_names_to_keys ||= catalog.class_names_to_keys
        end

        def relevant_class_names
          workflow_key.present? ? catalog.class_names_for(workflow_key) : class_names_to_keys.keys
        end
      end
    end
  end
end

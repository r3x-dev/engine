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
          runs = jobs.filter_map { |job| build_run(job) }
          runs.select! { |run| run[:workflow_key] == workflow_key } if workflow_key.present?
          runs.select! { |run| run[:status] == status } if status.present?
          runs.sort_by { |run| run[:recorded_at] || run[:enqueued_at] || Time.zone.at(0) }.reverse.first(limit)
        end

        def find!(job_id)
          @jobs = [ find_job!(job_id) ]

          build_run(@jobs.first) || raise(KeyError, "Unknown workflow run '#{job_id}'")
        rescue ActiveRecord::RecordNotFound
          raise KeyError, "Unknown workflow run '#{job_id}'"
        end

        private

        attr_reader :job_ids, :limit, :status, :workflow_key

        def build_run(job)
          resolved_workflow_key = class_names_to_keys[job.class_name]
          return if resolved_workflow_key.blank?

          trigger_key = job.trigger_key
          recurring_task = recurring_task_for(workflow_key: resolved_workflow_key, trigger_key: trigger_key)

          {
            active_job_id: job.active_job_id,
            class_name: job.class_name,
            enqueued_at: job.created_at,
            error: job.failed_execution&.error,
            finished_at: job.finished_at,
            job_id: job.id,
            known_workflow: class_names_to_keys.key?(job.class_name),
            mission_control_path: "/ops/jobs",
            priority: job.priority,
            queue_name: job.queue_name,
            recorded_at: job.recorded_at,
            scheduled_at: job.scheduled_execution&.scheduled_at || job.scheduled_at,
            started_at: job.claimed_execution&.created_at || job.created_at,
            status: job.status,
            trigger_key: trigger_key,
            trigger_payload: job.trigger_payload,
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

          [ limit * 10, DEFAULT_LIMIT ].max
        end
      end
    end
  end
end

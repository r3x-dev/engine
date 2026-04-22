module R3x
  module Dashboard
    class WorkflowRuns
      DEFAULT_LIMIT = 50
      LEGACY_CLASS_NAME = "R3x::RunWorkflowJob"
      CHANGE_DETECTION_CLASS_NAME = "R3x::ChangeDetectionJob"
      STATUSES = %w[ blocked failed finished queued running scheduled ].freeze

      def self.statuses
        STATUSES
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
        runs
          .sort_by { |run| run[:recorded_at] || run[:enqueued_at] || Time.at(0) }
          .reverse
          .first(limit)
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
          workflow_key = workflow_key_for(job)
          return if workflow_key.blank?

          failed_execution = failed_executions_by_job_id[job.id]
          payload = JobPayload.new(job.arguments)

          {
            active_job_id: job.active_job_id,
            class_name: job.class_name,
            enqueued_at: job.created_at,
            error: failed_execution&.error,
            finished_at: job.finished_at,
            job_id: job.id,
            known_workflow: catalog.workflow_keys.include?(workflow_key),
            mission_control_path: "/ops/jobs",
            priority: job.priority,
            queue_name: job.queue_name,
            recorded_at: recorded_at_for(job, failed_execution: failed_execution),
            scheduled_at: scheduled_executions_by_job_id[job.id]&.scheduled_at || job.scheduled_at,
            status: status_for(job),
            trigger_key: trigger_key_for(job, payload: payload),
            trigger_payload: trigger_payload_for(payload: payload),
            workflow_key: workflow_key,
            workflow_title: workflow_key.titleize
          }
        end

        def find_job!(job_id)
          SolidQueue::Job.find(job_id)
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

        def workflow_key_for(job)
          payload = JobPayload.new(job.arguments)
          return payload.legacy_workflow_key if job.class_name == LEGACY_CLASS_NAME
          return nil if job.class_name == CHANGE_DETECTION_CLASS_NAME

          catalog.class_names_to_keys[job.class_name]
        end

        def trigger_key_for(job, payload:)
          if job.class_name == LEGACY_CLASS_NAME
            options = payload.options
            options["trigger_key"] || options[:trigger_key]
          else
            payload.workflow_arguments.first
          end
        end

        def trigger_payload_for(payload:)
          payload.trigger_payload
        end

        def status_for(job)
          return "failed" if failed_executions_by_job_id.key?(job.id)
          return "finished" if job.finished_at.present?
          return "running" if claimed_executions_by_job_id.key?(job.id)
          return "queued" if ready_executions_by_job_id.key?(job.id)
          return "blocked" if blocked_executions_by_job_id.key?(job.id)
          return "scheduled" if scheduled_executions_by_job_id.key?(job.id)

          "queued"
        end

        def recorded_at_for(job, failed_execution:)
          case status_for(job)
          when "failed"
            failed_execution&.created_at || job.updated_at
          when "running"
            claimed_executions_by_job_id[job.id]&.created_at || job.updated_at
          when "queued"
            ready_executions_by_job_id[job.id]&.created_at || job.created_at
          when "blocked"
            blocked_executions_by_job_id[job.id]&.created_at || job.created_at
          when "scheduled"
            scheduled_executions_by_job_id[job.id]&.scheduled_at || job.scheduled_at || job.created_at
          else
            job.finished_at || job.updated_at
          end
        end

        def blocked_executions_by_job_id
          @blocked_executions_by_job_id ||= load_execution_map(SolidQueue::BlockedExecution)
        end

        def claimed_executions_by_job_id
          @claimed_executions_by_job_id ||= load_execution_map(SolidQueue::ClaimedExecution)
        end

        def failed_executions_by_job_id
          @failed_executions_by_job_id ||= load_execution_map(SolidQueue::FailedExecution)
        end

        def ready_executions_by_job_id
          @ready_executions_by_job_id ||= load_execution_map(SolidQueue::ReadyExecution)
        end

        def scheduled_executions_by_job_id
          @scheduled_executions_by_job_id ||= load_execution_map(SolidQueue::ScheduledExecution)
        end

        def load_execution_map(model)
          return {} if jobs.empty?

          model.where(job_id: jobs.map(&:id)).index_by(&:job_id)
        end

        def catalog
          @catalog ||= WorkflowCatalog.new
        end

        def jobs_scope
          scope = SolidQueue::Job.where(class_name: relevant_class_names)
          return scope if status.blank?

          scope.where(id: status_job_ids)
        end

        def relevant_class_names
          if workflow_key.present?
            catalog.class_names_for(workflow_key) + [ LEGACY_CLASS_NAME ]
          else
            catalog.class_names_to_keys.keys + [ LEGACY_CLASS_NAME ]
          end.uniq
        end

        def status_job_ids
          case status
          when "blocked"
            SolidQueue::BlockedExecution.select(:job_id)
          when "failed"
            SolidQueue::FailedExecution.select(:job_id)
          when "finished"
            SolidQueue::Job
              .where.not(finished_at: nil)
              .where.not(id: SolidQueue::FailedExecution.select(:job_id))
              .select(:id)
          when "queued"
            SolidQueue::ReadyExecution.select(:job_id)
          when "running"
            SolidQueue::ClaimedExecution.select(:job_id)
          when "scheduled"
            SolidQueue::ScheduledExecution.select(:job_id)
          else
            raise ArgumentError, "Unsupported status: #{status}"
          end
        end

        def query_limit
          return nil if job_ids.present?
          return limit unless workflow_key.present? || status.present?

          [ limit * 10, DEFAULT_LIMIT ].max
        end
    end
  end
end

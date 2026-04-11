module R3x
  module Dashboard
    class WorkflowRuns
      DEFAULT_LIMIT = 50
      LEGACY_CLASS_NAME = "R3x::RunWorkflowJob"
      STATUSES = %w[ blocked failed finished queued running scheduled ].freeze

      def self.statuses
        STATUSES
      end

      def initialize(workflow_key: nil, status: nil, limit: DEFAULT_LIMIT)
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

      private
        attr_reader :limit, :status, :workflow_key

        def build_run(job)
          workflow_key = workflow_key_for(job)
          return if workflow_key.blank?

          failed_execution = failed_executions_by_job_id[job.id]

          {
            active_job_id: job.active_job_id,
            class_name: job.class_name,
            enqueued_at: job.created_at,
            error: failed_execution&.error,
            finished_at: job.finished_at,
            job_id: job.id,
            known_workflow: workflow_keys.include?(workflow_key),
            mission_control_path: "/ops/jobs",
            queue_name: job.queue_name,
            recorded_at: recorded_at_for(job, failed_execution: failed_execution),
            scheduled_at: scheduled_executions_by_job_id[job.id]&.scheduled_at || job.scheduled_at,
            status: status_for(job),
            trigger_key: trigger_key_for(job),
            workflow_key: workflow_key,
            workflow_title: workflow_key.titleize
          }
        end

        def jobs
          @jobs ||= begin
            SolidQueue::Job
              .where(class_name: relevant_class_names)
              .order(created_at: :desc)
              .limit(query_limit)
              .to_a
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            []
          end
        end

        def relevant_class_names
          if workflow_key.present?
            [ workflow_class_name, LEGACY_CLASS_NAME ].compact.uniq
          else
            workflow_classes.map(&:name) + [ LEGACY_CLASS_NAME ]
          end
        end

        def workflow_class_name
          workflow_classes.find { |workflow_class| workflow_class.workflow_key == workflow_key }&.name
        end

        def workflow_key_for(job)
          return class_names_to_keys[job.class_name] unless job.class_name == LEGACY_CLASS_NAME

          arguments = normalize_arguments(job.arguments)
          arguments.first.presence || options_for(arguments)["workflow_key"] || options_for(arguments)[:workflow_key]
        end

        def trigger_key_for(job)
          arguments = normalize_arguments(job.arguments)

          if job.class_name == LEGACY_CLASS_NAME
            options = options_for(arguments)
            options["trigger_key"] || options[:trigger_key]
          else
            arguments.first
          end
        end

        def options_for(arguments)
          arguments.second.is_a?(Hash) ? arguments.second : {}
        end

        def normalize_arguments(arguments)
          Array(arguments).map { |argument| normalize_argument(argument) }
        end

        def normalize_argument(argument)
          case argument
          when Array
            argument.map { |item| normalize_argument(item) }
          when Hash
            normalize_hash(argument)
          else
            argument
          end
        end

        def normalize_hash(argument)
          argument.each_with_object({}) do |(key, value), normalized|
            normalized[key] = normalize_argument(value)
          end.tap do |normalized|
            symbolize_marked_keys!(normalized, "_aj_ruby2_keywords")
            symbolize_marked_keys!(normalized, "_aj_symbol_keys")
          end
        end

        def symbolize_marked_keys!(hash, marker)
          Array(hash.delete(marker)).each do |key|
            next unless hash.key?(key)

            hash[key.to_sym] = hash.delete(key)
          end
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

        def workflow_classes
          @workflow_classes ||= R3x::Workflow::Registry.all
        end

        def workflow_keys
          @workflow_keys ||= workflow_classes.map(&:workflow_key)
        end

        def class_names_to_keys
          @class_names_to_keys ||= workflow_classes.each_with_object({}) do |workflow_class, mapping|
            mapping[workflow_class.name] = workflow_class.workflow_key
          end
        end

        def query_limit
          return limit unless workflow_key.present? || status.present?

          [ limit * 10, DEFAULT_LIMIT ].max
        end
    end
  end
end

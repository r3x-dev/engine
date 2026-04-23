module Dashboard
  class Run < ApplicationRecord
    include R3x::Concerns::Logger

    CHANGE_DETECTION_CLASS_NAME = "R3x::ChangeDetectionJob"
    IGNORED_CLASS_NAMES = [ CHANGE_DETECTION_CLASS_NAME ].freeze
    STATUSES = %w[ blocked failed finished queued running scheduled ].freeze

    self.table_name = "solid_queue_jobs"

    serialize :arguments, coder: JSON

    has_one :recurring_execution, class_name: "SolidQueue::RecurringExecution", foreign_key: :job_id
    has_one :failed_execution, class_name: "SolidQueue::FailedExecution", foreign_key: :job_id
    has_one :scheduled_execution, class_name: "SolidQueue::ScheduledExecution", foreign_key: :job_id
    has_one :blocked_execution, class_name: "SolidQueue::BlockedExecution", foreign_key: :job_id
    has_one :ready_execution, class_name: "SolidQueue::ReadyExecution", foreign_key: :job_id
    has_one :claimed_execution, class_name: "SolidQueue::ClaimedExecution", foreign_key: :job_id

    scope :with_execution_associations, -> { includes(:failed_execution, :scheduled_execution, :blocked_execution, :ready_execution, :claimed_execution) }
    scope :excluding_ignored_classes, -> { where.not(class_name: IGNORED_CLASS_NAMES) }
    scope :dashboard_visible, ->(class_names) do
      visible_class_names = Array(class_names).compact_blank
      visible_class_names.present? ? where(class_name: visible_class_names) : none
    end
    scope :direct_workflows, -> { excluding_ignored_classes.where("class_name LIKE ?", "Workflows::%") }
    scope :observed_triggers, -> { excluding_ignored_classes.where(class_name: []) }
    scope :unfinished, -> { where(finished_at: nil).where.missing(:failed_execution) }
    scope :for_status, ->(status) do
      case status.to_s
      when ""
        all
      when "blocked"
        unfinished
          .where.missing(:claimed_execution)
          .joins(:blocked_execution)
      when "failed"
        joins(:failed_execution)
      when "finished"
        where.not(finished_at: nil).where.missing(:failed_execution)
      when "queued"
        unfinished
          .where.missing(:claimed_execution)
          .where.missing(:blocked_execution)
          .where.missing(:scheduled_execution)
      when "running"
        unfinished.joins(:claimed_execution)
      when "scheduled"
        unfinished
          .where.missing(:claimed_execution)
          .where.missing(:blocked_execution)
          .joins(:scheduled_execution)
      else
        raise ArgumentError, "Unsupported status: #{status}"
      end
    end

    class EnqueueError < StandardError; end

    class << self
      def enqueue_direct!(class_name:, arguments:, queue_name:, priority:)
        active_job = build_active_job(
          class_name: class_name,
          arguments: arguments,
          queue_name: queue_name,
          priority: priority
        )
        enqueued_job = SolidQueue::Job.enqueue(active_job)

        find(enqueued_job.id)
      rescue ActiveJob::SerializationError, ActiveRecord::ActiveRecordError, SolidQueue::Job::EnqueueError => e
        logger.error(
          "Dashboard direct enqueue failed class_name=#{class_name} " \
          "queue=#{queue_name.presence || 'default'} priority=#{priority.inspect} " \
          "error_class=#{e.class} error_message=#{e.message}"
        )

        raise EnqueueError, "Direct workflow enqueue failed for #{class_name}: #{e.message}"
      end

      def trigger_enqueue_options_for(task)
        return if task.blank? || task.direct_workflow_class_name.blank?

        {
          class_name: task.direct_workflow_class_name,
          arguments: task.arguments,
          queue_name: task.queue_name,
          priority: task.priority
        }
      end

      def manual_enqueue_options_for(workflow_key:, class_name: nil, recurring_task: nil, last_run: nil)
        resolved_class_name =
          class_name.presence ||
          recurring_task&.direct_workflow_class_name ||
          last_run&.class_name ||
          default_workflow_class_name(workflow_key)

        return if resolved_class_name.blank?

        {
          class_name: resolved_class_name,
          arguments: [],
          queue_name: recurring_task&.queue_name || last_run&.queue_name,
          priority: recurring_task&.priority || last_run&.priority
        }
      end

      def recent_ids(limit:, class_names:)
        base_scope = dashboard_visible(class_names)

        [
          base_scope.for_status("failed").order("solid_queue_failed_executions.created_at DESC").limit(limit).pluck(:id),
          base_scope.for_status("finished").order(finished_at: :desc).limit(limit).pluck(:id),
          base_scope.for_status("running").order("solid_queue_claimed_executions.created_at DESC").limit(limit).pluck(:id),
          base_scope.for_status("queued").joins(:ready_execution).order("solid_queue_ready_executions.created_at DESC").limit(limit).pluck(:id),
          base_scope.for_status("queued").where.missing(:ready_execution).order(created_at: :desc).limit(limit).pluck(:id),
          base_scope.for_status("blocked").order("solid_queue_blocked_executions.created_at DESC").limit(limit).pluck(:id),
          base_scope.for_status("scheduled").order("solid_queue_scheduled_executions.scheduled_at DESC").limit(limit).pluck(:id)
        ].flatten.uniq
      end

      def normalize_arguments(argument)
        case argument
        when Array
          argument.map { |item| normalize_arguments(item) }
        when Hash
          normalize_hash(argument)
        else
          argument
        end
      end

      def default_workflow_class_name(workflow_key)
        "Workflows::#{workflow_key.to_s.camelize}"
      end

      private
        def normalize_hash(argument)
          argument.each_with_object({}) do |(key, value), normalized|
            normalized[key] = normalize_arguments(value)
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

        def build_active_job(class_name:, arguments:, queue_name:, priority:)
          job_class_name = class_name.to_s
          direct_job_class = Class.new(ActiveJob::Base) do
            def perform(*)
            end
          end

          direct_job_class.define_singleton_method(:name) { job_class_name }
          direct_job_class.queue_name = queue_name if queue_name.present?
          direct_job_class.priority = priority unless priority.nil?

          positional_arguments, keyword_arguments = split_arguments(arguments)

          if keyword_arguments.empty?
            direct_job_class.new(*positional_arguments)
          else
            direct_job_class.new(*positional_arguments, **keyword_arguments)
          end
        end

        def split_arguments(raw_arguments)
          positional_arguments = Array(normalize_arguments(raw_arguments)).dup
          keyword_arguments = positional_arguments.last.is_a?(Hash) ? positional_arguments.pop.transform_keys(&:to_sym) : {}

          [ positional_arguments, keyword_arguments ]
        end
    end

    def status
      return "failed" if failed_execution.present?
      return "finished" if finished_at.present?
      return "running" if claimed_execution.present?
      return "blocked" if blocked_execution.present?
      return "scheduled" if scheduled_execution.present?
      return "queued" if ready_execution.present?

      "queued"
    end

    def recorded_at
      case status
      when "failed"
        failed_execution&.created_at || updated_at
      when "running"
        claimed_execution&.created_at || updated_at
      when "queued"
        ready_execution&.created_at || created_at
      when "blocked"
        blocked_execution&.created_at || created_at
      when "scheduled"
        scheduled_execution&.scheduled_at || scheduled_at || created_at
      else
        finished_at || updated_at
      end
    end

    def workflow_arguments
      @workflow_arguments ||= if serialized_active_job_payload?
        Array(fetch_key(normalized_arguments, "arguments"))
      else
        Array(normalized_arguments)
      end
    end

    def trigger_key
      candidate = workflow_arguments.first
      return candidate if candidate.is_a?(String) && candidate.present?

      nil
    end

    def trigger_payload
      options = workflow_arguments.second
      return unless options.is_a?(Hash)

      options["trigger_payload"] || options[:trigger_payload]
    end

    private
      def normalized_arguments
        @normalized_arguments ||= self.class.normalize_arguments(arguments)
      end

      def serialized_active_job_payload?
        normalized_arguments.is_a?(Hash) &&
          fetch_key(normalized_arguments, "job_class").present? &&
          normalized_arguments.key?("arguments")
      end

      def fetch_key(hash, key)
        hash[key] || hash[key.to_sym]
      end
  end
end

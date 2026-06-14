module Dashboard
  class Run < ApplicationRecord
    include R3x::Concerns::Logger

    STATUSES = %w[blocked failed finished queued running scheduled].freeze
    LATEST_ACTIVITY_BUCKETS = [
      [ "failed", :solid_queue_failed_executions, :created_at ],
      [ "finished", :solid_queue_jobs, :finished_at ],
      [ "running", :solid_queue_claimed_executions, :created_at ],
      [ "queued_ready", :solid_queue_ready_executions, :created_at ],
      [ "queued_waiting", :solid_queue_jobs, :created_at ],
      [ "blocked", :solid_queue_blocked_executions, :created_at ],
      [ "scheduled", :solid_queue_scheduled_executions, :scheduled_at ]
    ].freeze

    self.table_name = "solid_queue_jobs"

    serialize :arguments, coder: JSON

    has_one :recurring_execution, class_name: "SolidQueue::RecurringExecution", foreign_key: :job_id
    has_one :failed_execution, class_name: "SolidQueue::FailedExecution", foreign_key: :job_id
    has_one :scheduled_execution, class_name: "SolidQueue::ScheduledExecution", foreign_key: :job_id
    has_one :blocked_execution, class_name: "SolidQueue::BlockedExecution", foreign_key: :job_id
    has_one :ready_execution, class_name: "SolidQueue::ReadyExecution", foreign_key: :job_id
    has_one :claimed_execution, class_name: "SolidQueue::ClaimedExecution", foreign_key: :job_id

    scope :with_execution_associations, -> {
      includes(:failed_execution, :scheduled_execution, :blocked_execution, :ready_execution, :claimed_execution)
    }
    scope :dashboard_visible, ->(class_names) do
      visible_class_names = Array(class_names).compact_blank
      visible_class_names.present? ? where(class_name: visible_class_names) : none
    end
    scope :direct_workflows, -> { where("class_name LIKE ?", "Workflows::%") }
    scope :observed_triggers, -> { where(class_name: []) }
    scope :unfinished, -> { where(finished_at: nil).where.missing(:failed_execution) }
    scope :for_status, ->(status) do
      case status.to_s
      when ""
        all
      when "blocked"
        unfinished.where.missing(:claimed_execution).joins(:blocked_execution)
      when "failed"
        joins(:failed_execution)
      when "finished"
        where.not(finished_at: nil).where.missing(:failed_execution)
      when "queued"
        unfinished.where.missing(:claimed_execution).where.missing(:blocked_execution).where.missing(:scheduled_execution)
      when "running"
        unfinished.joins(:claimed_execution)
      when "scheduled"
        unfinished.where.missing(:claimed_execution).where.missing(:blocked_execution).joins(:scheduled_execution)
      else
        raise ArgumentError, "Unsupported status: #{status}"
      end
    end

    class EnqueueError < StandardError; end

    class << self
      def enqueue_direct!(class_name:, arguments:, queue_name:, priority:)
        Dashboard::DirectWorkflowEnqueuer.enqueue!(class_name: class_name, arguments: arguments, queue_name: queue_name, priority: priority)
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
        resolved_class_name = class_name.presence ||
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

        LATEST_ACTIVITY_BUCKETS.flat_map do |status, table_name, column_name|
          latest_activity_status_scope(base_scope, status).order(Arel::Table.new(table_name)[column_name].desc).limit(limit).pluck(:id)
        end.uniq
      end

      def latest_activity_candidates(class_names:)
        ids = latest_activity_candidate_ids(class_names:)
        return [] if ids.empty?

        with_execution_associations.where(id: ids).to_a
      rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
        []
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
        normalized = argument.each_with_object({}) do |(key, value), hash|
          hash[key] = normalize_arguments(value)
        end
        symbolize_marked_keys!(normalized, "_aj_ruby2_keywords")
        symbolize_marked_keys!(normalized, "_aj_symbol_keys")
        normalized
      end

      def symbolize_marked_keys!(hash, marker)
        Array(hash.delete(marker)).each do |key|
          next unless hash.key?(key)

          hash[key.to_sym] = hash.delete(key)
        end
      end

      # Returns the latest activity run candidate IDs for the specified workflow class names.
      # To avoid N+1 database round-trips when fetching the latest run for each execution status,
      # we generate ranked subqueries for each of the 7 statuses and combine them using a UNION.
      #
      # Note: This UNION is highly performant and safe from query planner bloating because the number
      # of buckets (7) is static and we only project the indexed job ID fields.
      def latest_activity_candidate_ids(class_names:)
        visible_class_names = Array(class_names).compact_blank
        return [] if visible_class_names.empty?

        base_scope = dashboard_visible(visible_class_names)

        sqls = LATEST_ACTIVITY_BUCKETS.map do |status, table_name, column_name|
          recorded_at = Arel::Table.new(table_name)[column_name]
          ranked_sql = latest_activity_status_scope(base_scope, status)
                       .select(run_table[:id].as("id"), latest_activity_rank(recorded_at).as("dashboard_rank"))
                       .to_sql
          "SELECT id FROM (#{ranked_sql}) dashboard_latest_runs WHERE dashboard_rank = 1"
        end

        connection.select_values(sqls.join(" UNION "))
      end

      def latest_activity_status_scope(base_scope, status)
        case status
        when "queued_ready"
          base_scope.for_status("queued").joins(:ready_execution)
        when "queued_waiting"
          base_scope.for_status("queued").where.missing(:ready_execution)
        else
          base_scope.for_status(status)
        end
      end

      def latest_activity_rank(recorded_at)
        window = Arel::Nodes::Window.new.partition(run_table[:class_name]).order(recorded_at.desc, run_table[:id].desc)

        Arel::Nodes::Over.new(Arel::Nodes::NamedFunction.new("ROW_NUMBER", []), window)
      end

      def run_table
        arel_table
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

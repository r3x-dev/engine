require "fugit"

module R3x
  module Dashboard
    module Workflow
      class Summaries
        DEFAULT_SORT = "health"
        DEFAULT_DIRECTIONS = { "workflow" => "asc", "health" => "asc", "next_trigger" => "asc", "last_run" => "desc" }.freeze
        HEALTH_SORT_ORDER = %w[failed healthy idle].freeze

        attr_reader :direction, :sort

        def self.default_direction_for(sort)
          DEFAULT_DIRECTIONS.fetch(normalize_sort(sort))
        end

        def self.normalize_direction(direction, sort:)
          normalized_direction = direction.to_s
          return default_direction_for(sort) unless %w[asc desc].include?(normalized_direction)

          normalized_direction
        end

        def self.normalize_sort(sort)
          normalized_sort = sort.to_s
          return DEFAULT_SORT unless DEFAULT_DIRECTIONS.key?(normalized_sort)

          normalized_sort
        end

        def initialize(sort: nil, direction: nil)
          @sort = self.class.normalize_sort(sort)
          @direction = self.class.normalize_direction(direction, sort: @sort)
        end

        def all
          workflows = catalog.all.map { |workflow| build_summary(workflow.fetch(:workflow_key)) }

          workflows.sort { |left, right| compare_workflows(left, right) }
        end

        def find!(workflow_key)
          catalog.find!(workflow_key)

          build_summary(workflow_key)
        end

        private

        def build_summary(workflow_key)
          recurring_tasks = recurring_tasks_by_workflow_key.fetch(workflow_key, [])
          trigger_entries = trigger_entries_for(workflow_key:, recurring_tasks:)
          last_run = latest_run_for(workflow_key)
          preferred_recurring_task = recurring_tasks.find { |task| task.direct_workflow_class_name.present? } || recurring_tasks.first
          manual_enqueue_options = ::Dashboard::Run.manual_enqueue_options_for(
            workflow_key: workflow_key,
            class_name: preferred_recurring_task&.direct_workflow_class_name,
            recurring_task: preferred_recurring_task,
            last_run: last_run
          )

          {
            class_name: manual_enqueue_options&.fetch(:class_name),
            health: health_for(last_run: last_run),
            last_seen_at: last_seen_at_for(last_run: last_run),
            last_run: last_run && build_run_summary(last_run, workflow_key),
            mission_control_path: "/ops/jobs",
            next_trigger_at: trigger_entries.filter_map { |entry| entry[:next_trigger_at] }.min,
            run_now_available: manual_enqueue_options.present?,
            title: workflow_key.titleize,
            trigger_count: trigger_entries.size,
            trigger_entries: trigger_entries,
            workflow_key: workflow_key
          }
        end

        def build_run_summary(run, workflow_key)
          {
            class_name: run.class_name,
            error: run.failed_execution&.error,
            job_id: run.id,
            priority: run.priority,
            queue_name: run.queue_name,
            recorded_at: run.recorded_at,
            status: run.status,
            workflow_key: workflow_key
          }
        end

        def compare_workflows(left, right)
          comparison = case sort
          when "workflow"
            compare_text(left[:title], right[:title], direction:)
          when "health"
            compare_health(left, right)
          when "next_trigger"
            compare_time(left[:next_trigger_at], right[:next_trigger_at], direction:)
          when "last_run"
            compare_time(left.dig(:last_run, :recorded_at), right.dig(:last_run, :recorded_at), direction:)
          else
            raise ArgumentError, "Unsupported workflow sort: #{sort}"
          end

          return comparison unless comparison.zero?

          left[:workflow_key] <=> right[:workflow_key]
        end

        def compare_health(left, right)
          comparison = compare_numbers(health_rank(left.dig(:health, :status)), health_rank(right.dig(:health, :status)), direction:)
          return comparison unless comparison.zero?

          comparison = compare_time(health_timestamp_for(left), health_timestamp_for(right), direction: "desc")
          return comparison unless comparison.zero?

          compare_text(left[:title], right[:title], direction: "asc")
        end

        def compare_numbers(left, right, direction:)
          comparison = left <=> right
          (direction == "desc") ? -comparison : comparison
        end

        def compare_text(left, right, direction:)
          comparison = left.to_s.downcase <=> right.to_s.downcase
          (direction == "desc") ? -comparison : comparison
        end

        def compare_time(left, right, direction:)
          return 0 if left.blank? && right.blank?
          return 1 if left.blank?
          return -1 if right.blank?

          comparison = left <=> right
          (direction == "desc") ? -comparison : comparison
        end

        def health_rank(status)
          HEALTH_SORT_ORDER.index(status.to_s) || HEALTH_SORT_ORDER.length
        end

        def health_timestamp_for(workflow)
          workflow.dig(:last_run, :recorded_at) || workflow[:last_seen_at]
        end

        def trigger_entries_for(workflow_key:, recurring_tasks:)
          trigger_keys = recurring_tasks.map(&:trigger_key)
          recurring_tasks_by_trigger_key = recurring_tasks.index_by(&:trigger_key)

          trigger_keys.sort.map do |trigger_key|
            build_trigger_entry(
              workflow_key: workflow_key,
              trigger_key: trigger_key,
              recurring_task: recurring_tasks_by_trigger_key[trigger_key]
            )
          end
        end

        def build_trigger_entry(workflow_key:, trigger_key:, recurring_task:)
          {
            cron: recurring_task&.schedule,
            mode: trigger_mode_for(recurring_task),
            next_trigger_at: next_trigger_at_for(recurring_task),
            queue_name: recurring_task&.queue_name || latest_queue_name(workflow_key),
            recurring_task: recurring_task,
            run_now_available: recurring_task.present?,
            unique_key: trigger_key,
            workflow_key: workflow_key
          }
        end

        def health_for(last_run:)
          return failed_run_health(last_run) if last_run&.status == "failed"
          return healthy_health if last_run.present?

          idle_health
        end

        def failed_run_health(last_run)
          {
            detail: last_run.failed_execution&.error,
            label: "Last run failed",
            status: "failed"
          }
        end

        def healthy_health
          {
            detail: nil,
            label: "Healthy",
            status: "healthy"
          }
        end

        def idle_health
          {
            detail: nil,
            label: "No runs yet",
            status: "idle"
          }
        end

        def next_trigger_at_for(recurring_task)
          return if recurring_task.blank?

          parsed = Fugit.parse(recurring_task.schedule, multi: :fail)
          return unless parsed.is_a?(Fugit::Cron)

          parsed.next_time(Time.current).to_t
        rescue ArgumentError
          nil
        end

        def recurring_tasks_by_workflow_key
          @recurring_tasks_by_workflow_key ||= begin
            ::Dashboard::RecurringTask.workflow_tasks.to_a.group_by(&:workflow_key)
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            {}
          end
        end

        def catalog
          @catalog ||= Workflow::Catalog.new
        end

        def trigger_mode_for(recurring_task)
          return "scheduled" if recurring_task.present?

          "observed"
        end

        def last_seen_at_for(last_run:)
          last_run&.recorded_at
        end

        def latest_queue_name(workflow_key)
          latest_run_for(workflow_key)&.queue_name
        end

        def latest_run_for(workflow_key)
          latest_runs_by_workflow_key[workflow_key.to_s]
        end

        def latest_runs_by_workflow_key
          @latest_runs_by_workflow_key ||= latest_visible_runs.each_with_object({}) do |run, latest_runs|
            workflow_key = catalog.class_names_to_keys[run.class_name]
            next if workflow_key.blank?

            latest_run = latest_runs[workflow_key]
            latest_runs[workflow_key] = run if latest_run.blank? || compare_latest_runs(run, latest_run).positive?
          end
        end

        def latest_visible_runs
          ::Dashboard::Run.latest_activity_candidates(class_names: catalog.class_names_to_keys.keys)
        end

        def compare_latest_runs(left, right)
          left_time = left.recorded_at || left.created_at || Time.at(0)
          right_time = right.recorded_at || right.created_at || Time.at(0)
          comparison = left_time <=> right_time
          return comparison unless comparison.zero?

          left.id <=> right.id
        end
      end
    end
  end
end

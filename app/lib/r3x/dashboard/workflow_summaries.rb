require "fugit"

module R3x
  module Dashboard
    class WorkflowSummaries
      DEFAULT_SORT = "health"
      DEFAULT_DIRECTIONS = {
        "workflow" => "asc",
        "health" => "asc",
        "next_trigger" => "asc",
        "last_run" => "desc"
      }.freeze
      HEALTH_SORT_ORDER = %w[trigger_error failed healthy idle].freeze

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
          trigger_states = trigger_states_by_workflow_key.fetch(workflow_key, [])
          recurring_tasks = recurring_tasks_by_workflow_key.fetch(workflow_key, [])
          trigger_entries = trigger_entries_for(workflow_key:, trigger_states:, recurring_tasks:)
          last_run = WorkflowRuns.new(workflow_key: workflow_key, limit: 1).all.first
          class_name = recurring_tasks.filter_map { |task| workflow_class_name(task) }.first || last_run&.dig(:class_name)

          {
            class_name: class_name,
            health: health_for(last_run: last_run, trigger_states: trigger_states),
            last_seen_at: last_seen_at_for(last_run: last_run, trigger_states: trigger_states),
            last_run: last_run,
            mission_control_path: "/ops/jobs",
            next_trigger_at: trigger_entries.filter_map { |entry| entry[:next_trigger_at] }.min,
            title: workflow_key.titleize,
            trigger_count: trigger_entries.size,
            trigger_entries: trigger_entries,
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
            0
          end

          return comparison unless comparison.zero?

          left[:workflow_key] <=> right[:workflow_key]
        end

        def compare_health(left, right)
          comparison = compare_numbers(
            health_rank(left.dig(:health, :status)),
            health_rank(right.dig(:health, :status)),
            direction:
          )
          return comparison unless comparison.zero?

          comparison = compare_time(health_timestamp_for(left), health_timestamp_for(right), direction: "desc")
          return comparison unless comparison.zero?

          compare_text(left[:title], right[:title], direction: "asc")
        end

        def compare_numbers(left, right, direction:)
          comparison = left <=> right
          direction == "desc" ? -comparison : comparison
        end

        def compare_text(left, right, direction:)
          comparison = left.to_s.downcase <=> right.to_s.downcase
          direction == "desc" ? -comparison : comparison
        end

        def compare_time(left, right, direction:)
          return 0 if left.blank? && right.blank?
          return 1 if left.blank?
          return -1 if right.blank?

          comparison = left <=> right
          direction == "desc" ? -comparison : comparison
        end

        def health_rank(status)
          HEALTH_SORT_ORDER.index(status.to_s) || HEALTH_SORT_ORDER.length
        end

        def health_timestamp_for(workflow)
          return workflow[:last_seen_at] if workflow.dig(:health, :status) == "trigger_error"

          workflow.dig(:last_run, :recorded_at) || workflow[:last_seen_at]
        end

        def trigger_entries_for(workflow_key:, trigger_states:, recurring_tasks:)
          trigger_keys = recurring_tasks.filter_map do |task|
            parse_task_key(task.key)&.fetch(:trigger_key)
          end

          trigger_keys |= trigger_states.map(&:trigger_key)

          trigger_keys.sort.map do |trigger_key|
            build_trigger_entry(
              workflow_key: workflow_key,
              trigger_key: trigger_key,
              trigger_states: trigger_states,
              recurring_tasks: recurring_tasks
            )
          end
        end

        def build_trigger_entry(workflow_key:, trigger_key:, trigger_states:, recurring_tasks:)
          recurring_task = recurring_tasks.find { |task| parse_task_key(task.key)&.fetch(:trigger_key) == trigger_key }
          trigger_state = trigger_states.find { |state| state.trigger_key == trigger_key }

          {
            change_detecting: change_detecting_trigger?(recurring_task, trigger_state),
            cron: recurring_task&.schedule,
            mode: trigger_mode_for(recurring_task, trigger_state),
            next_trigger_at: next_trigger_at_for(recurring_task),
            queue_name: recurring_task&.queue_name || latest_queue_name(workflow_key),
            recurring_task: recurring_task,
            run_now_available: recurring_task.present?,
            trigger_state: trigger_state,
            unique_key: trigger_key,
            workflow_key: workflow_key
          }
        end

        def health_for(last_run:, trigger_states:)
          trigger_error = trigger_states.select(&:last_error_at).max_by(&:last_error_at)
          return trigger_error_health(trigger_error) if trigger_error.present?

          if last_run&.dig(:status) == "failed"
            return {
              detail: last_run[:error],
              label: "Last run failed",
              status: "failed"
            }
          end

          if last_run.present?
            return {
              detail: nil,
              label: "Healthy",
              status: "healthy"
            }
          end

          {
            detail: nil,
            label: "No runs yet",
            status: "idle"
          }
        end

        def trigger_error_health(trigger_error)
          {
            detail: trigger_error.last_error_message,
            label: "Trigger error",
            status: "trigger_error"
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
            SolidQueue::RecurringTask
              .where("key LIKE ?", "workflow:%")
              .order(:key)
              .to_a
              .each_with_object({}) do |task, grouped|
                parsed_key = parse_task_key(task.key)
                next if parsed_key.nil?

                grouped[parsed_key.fetch(:workflow_key)] ||= []
                grouped[parsed_key.fetch(:workflow_key)] << task
              end
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            {}
          end
        end

        def trigger_states_by_workflow_key
          @trigger_states_by_workflow_key ||= begin
            R3x::TriggerState
              .order(:workflow_key, :trigger_key)
              .group_by(&:workflow_key)
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            {}
          end
        end

        def catalog
          @catalog ||= WorkflowCatalog.new
        end

        def parse_task_key(task_key)
          prefix, workflow_key, trigger_key = task_key.to_s.split(":", 3)
          return unless prefix == "workflow" && workflow_key.present? && trigger_key.present?

          { workflow_key: workflow_key, trigger_key: trigger_key }
        end

        def workflow_class_name(task)
          return if task.class_name == WorkflowCatalog::CHANGE_DETECTION_CLASS_NAME

          task.class_name.presence
        end

        def change_detecting_trigger?(recurring_task, trigger_state)
          return true if recurring_task&.class_name == WorkflowCatalog::CHANGE_DETECTION_CLASS_NAME

          trigger_state&.trigger_type.present? && !%w[ manual schedule ].include?(trigger_state.trigger_type) && recurring_task.blank?
        end

        def trigger_mode_for(recurring_task, trigger_state)
          return "change_detecting" if change_detecting_trigger?(recurring_task, trigger_state)
          return "scheduled" if recurring_task.present?
          return trigger_state.trigger_type if trigger_state&.trigger_type.present?

          "observed"
        end

        def last_seen_at_for(last_run:, trigger_states:)
          activity_times = [
            last_run&.dig(:recorded_at),
            *trigger_states.flat_map { |state| [ state.last_checked_at, state.last_triggered_at, state.last_error_at ] }
          ]

          activity_times.compact.max
        end

        def latest_queue_name(workflow_key)
          WorkflowRuns.new(workflow_key: workflow_key, limit: 1).all.first&.dig(:queue_name)
        end
    end
  end
end

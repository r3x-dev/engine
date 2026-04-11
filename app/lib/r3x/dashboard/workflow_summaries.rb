require "fugit"

module R3x
  module Dashboard
    class WorkflowSummaries
      def all
        workflow_classes.map { |workflow_class| build_summary(workflow_class) }
      end

      def find!(workflow_key)
        build_summary(R3x::Workflow::Registry.fetch(workflow_key))
      end

      private
        def build_summary(workflow_class)
          workflow_key = workflow_class.workflow_key
          trigger_states = trigger_states_by_workflow_key.fetch(workflow_key, [])
          recurring_tasks = recurring_tasks_by_workflow_key.fetch(workflow_key, [])
          trigger_entries = workflow_class.triggers.map do |trigger|
            build_trigger_entry(
              workflow_key: workflow_key,
              trigger: trigger,
              trigger_states: trigger_states,
              recurring_tasks: recurring_tasks
            )
          end
          last_run = WorkflowRuns.new(workflow_key: workflow_key, limit: 1).all.first

          {
            class_name: workflow_class.name,
            health: health_for(last_run: last_run, trigger_states: trigger_states),
            last_run: last_run,
            mission_control_path: "/ops/jobs",
            next_trigger_at: trigger_entries.filter_map { |entry| entry[:next_trigger_at] }.min,
            title: workflow_key.titleize,
            trigger_entries: trigger_entries,
            workflow_class: workflow_class,
            workflow_key: workflow_key
          }
        end

        def build_trigger_entry(workflow_key:, trigger:, trigger_states:, recurring_tasks:)
          {
            change_detecting: trigger.change_detecting?,
            cron: trigger.respond_to?(:cron) ? trigger.cron : nil,
            next_trigger_at: next_trigger_at_for(trigger),
            recurring_task: recurring_tasks.find { |task| task.key == recurring_task_key(workflow_key, trigger) },
            trigger: trigger,
            trigger_state: trigger_states.find { |state| state.trigger_key == trigger.unique_key },
            unique_key: trigger.unique_key
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

        def next_trigger_at_for(trigger)
          return unless trigger.cron_schedulable?

          parsed = Fugit.parse(trigger.cron, multi: :fail)
          return unless parsed.is_a?(Fugit::Cron)

          parsed.next_time(Time.current).to_t
        rescue ArgumentError
          nil
        end

        def recurring_task_key(workflow_key, trigger)
          "workflow:#{workflow_key}:#{trigger.unique_key}"
        end

        def recurring_tasks_by_workflow_key
          @recurring_tasks_by_workflow_key ||= begin
            SolidQueue::RecurringTask
              .where("key LIKE ?", "workflow:%")
              .order(:key)
              .to_a
              .group_by { |task| workflow_key_for(task.key) }
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            {}
          end
        end

        def workflow_key_for(task_key)
          task_key.to_s.split(":", 3)[1]
        end

        def trigger_states_by_workflow_key
          @trigger_states_by_workflow_key ||= begin
            R3x::TriggerState
              .where(workflow_key: workflow_classes.map(&:workflow_key))
              .order(:workflow_key, :trigger_key)
              .group_by(&:workflow_key)
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            {}
          end
        end

        def workflow_classes
          @workflow_classes ||= R3x::Workflow::Registry.all
        end
    end
  end
end

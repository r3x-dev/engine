module R3x
  module Dashboard
    class WorkflowCatalog
      CHANGE_DETECTION_CLASS_NAME = "R3x::ChangeDetectionJob"
      LEGACY_RUN_CLASS_NAME = "R3x::RunWorkflowJob"

      def all
        workflow_keys.map { |workflow_key| build_entry(workflow_key) }
      end

      def find!(workflow_key)
        workflow_key = workflow_key.to_s
        raise KeyError, "Unknown workflow '#{workflow_key}'" unless workflow_keys.include?(workflow_key)

        build_entry(workflow_key)
      end

      def workflow_keys
        @workflow_keys ||= begin
          keys = workflow_keys_from_recurring_tasks + workflow_keys_from_trigger_states + workflow_keys_from_legacy_runs
          keys.compact.uniq.sort
        end
      end

      def recurring_tasks_for(workflow_key)
        recurring_tasks_by_workflow_key.fetch(workflow_key.to_s, [])
      end

      def trigger_states_for(workflow_key)
        trigger_states_by_workflow_key.fetch(workflow_key.to_s, [])
      end

      def class_names_for(workflow_key)
        recurring_tasks_for(workflow_key)
          .filter_map { |task| concrete_workflow_class_name(task) }
          .uniq
      end

      def class_names_to_keys
        @class_names_to_keys ||= recurring_tasks.each_with_object({}) do |task, mapping|
          class_name = concrete_workflow_class_name(task)
          parsed_key = parse_task_key(task.key)
          next if class_name.blank? || parsed_key.nil?

          mapping[class_name] ||= parsed_key.fetch(:workflow_key)
        end
      end

      private
        def build_entry(workflow_key)
          recurring_tasks = recurring_tasks_for(workflow_key)

          {
            class_name: class_names_for(workflow_key).first,
            trigger_count: trigger_keys_for(workflow_key).size,
            workflow_key: workflow_key,
            title: workflow_key.titleize
          }
        end

        def trigger_keys_for(workflow_key)
          task_keys = recurring_tasks_for(workflow_key).filter_map do |task|
            parse_task_key(task.key)&.fetch(:trigger_key)
          end

          state_keys = trigger_states_for(workflow_key).map(&:trigger_key)

          (task_keys + state_keys).compact.uniq.sort
        end

        def workflow_keys_from_recurring_tasks
          recurring_tasks_by_workflow_key.keys
        end

        def workflow_keys_from_trigger_states
          trigger_states_by_workflow_key.keys
        end

        def workflow_keys_from_legacy_runs
          legacy_runs.filter_map do |job|
            JobPayload.new(job.arguments).legacy_workflow_key
          end
        end

        def recurring_tasks
          @recurring_tasks ||= begin
            SolidQueue::RecurringTask
              .where("key LIKE ?", "workflow:%")
              .order(:key)
              .to_a
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            []
          end
        end

        def recurring_tasks_by_workflow_key
          @recurring_tasks_by_workflow_key ||= recurring_tasks.each_with_object({}) do |task, grouped|
            parsed_key = parse_task_key(task.key)
            next if parsed_key.nil?

            grouped[parsed_key.fetch(:workflow_key)] ||= []
            grouped[parsed_key.fetch(:workflow_key)] << task
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

        def legacy_runs
          @legacy_runs ||= begin
            SolidQueue::Job
              .where(class_name: LEGACY_RUN_CLASS_NAME)
              .order(created_at: :desc)
              .limit(200)
              .to_a
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
            []
          end
        end

        def parse_task_key(task_key)
          prefix, workflow_key, trigger_key = task_key.to_s.split(":", 3)
          return unless prefix == "workflow" && workflow_key.present? && trigger_key.present?

          { workflow_key: workflow_key, trigger_key: trigger_key }
        end

        def concrete_workflow_class_name(task)
          return if task.class_name == CHANGE_DETECTION_CLASS_NAME

          task.class_name.presence
        end
    end
  end
end

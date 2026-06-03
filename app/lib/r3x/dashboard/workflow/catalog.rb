module R3x
  module Dashboard
    module Workflow
      class Catalog
        TRIGGER_OBSERVATION_JOB_LIMIT = 250

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
            keys = workflow_keys_from_recurring_tasks + observed_class_names_to_keys.values
            keys.compact.uniq.sort
          end
        end

        def recurring_tasks_for(workflow_key)
          recurring_tasks_by_workflow_key.fetch(workflow_key.to_s, [])
        end

        def class_names_for(workflow_key)
          class_names_by_workflow_key.fetch(workflow_key.to_s, [])
        end

        def class_names_to_keys
          @class_names_to_keys ||= recurring_task_class_names_to_keys.merge(observed_class_names_to_keys)
        end

        private
          def build_entry(workflow_key)
            {
              class_name: class_names_for(workflow_key).first,
              trigger_count: trigger_keys_for(workflow_key).size,
              workflow_key: workflow_key,
              title: workflow_key.titleize
            }
          end

          def trigger_keys_for(workflow_key)
            recurring_tasks_for(workflow_key).map(&:trigger_key).compact.uniq.sort
          end

          def workflow_keys_from_recurring_tasks
            recurring_tasks_by_workflow_key.keys
          end

          def recurring_tasks
            @recurring_tasks ||= begin
              ::Dashboard::RecurringTask.workflow_tasks.to_a
            rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
              []
            end
          end

          def recurring_tasks_by_workflow_key
            @recurring_tasks_by_workflow_key ||= recurring_tasks.group_by(&:workflow_key)
          end

          def recurring_task_class_names_to_keys
            @recurring_task_class_names_to_keys ||= recurring_tasks.each_with_object({}) do |task, mapping|
              class_name = task.direct_workflow_class_name
              next if class_name.blank?

              mapping[class_name] ||= task.workflow_key
            end
          end

          def class_names_by_workflow_key
            @class_names_by_workflow_key ||= class_names_to_keys.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(class_name, workflow_key), mapping|
              mapping[workflow_key] << class_name
            end
          end

          def observed_class_names_to_keys
            @observed_class_names_to_keys ||= begin
              mapping = observed_workflow_class_names_to_keys

              recent_trigger_observed_jobs.each do |job|
                next if mapping.key?(job.class_name)

                workflow_key = workflow_key_from_trigger(job)
                next if workflow_key.blank?

                mapping[job.class_name] = workflow_key
              end

              mapping
            end
          end

          def observed_workflow_class_names_to_keys
            @observed_workflow_class_names_to_keys ||= begin
              ::Dashboard::Run
                .direct_workflows
                .distinct
                .pluck(:class_name)
                .each_with_object({}) do |class_name, mapping|
                  workflow_key = workflow_key_from_class_name(class_name)
                  next if workflow_key.blank?

                  mapping[class_name] = workflow_key
                end
            rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
              {}
            end
          end

          def recent_trigger_observed_jobs
            @recent_trigger_observed_jobs ||= begin
              ::Dashboard::Run
                .observed_triggers
                .select(:class_name, :arguments)
                .order(created_at: :desc)
                .limit(TRIGGER_OBSERVATION_JOB_LIMIT)
                .to_a
            rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
              []
            end
          end

          def workflow_key_from_trigger(job)
            trigger_key = job.trigger_key
            return if trigger_key.blank?

            workflow_keys = trigger_keys_to_workflow_keys.fetch(trigger_key, [])
            return unless workflow_keys.one?

            workflow_keys.first
          end

          def workflow_key_from_class_name(class_name)
            return unless class_name.to_s.start_with?("Workflows::")

            class_name.demodulize.underscore
          end

          def trigger_keys_to_workflow_keys
            @trigger_keys_to_workflow_keys ||= begin
              mapping = Hash.new { |hash, key| hash[key] = [] }

              recurring_tasks.each do |task|
                mapping[task.trigger_key] << task.workflow_key
              end

              mapping.transform_values { |values| values.compact.uniq }
            end
          end
      end
    end
  end
end

# frozen_string_literal: true

module R3x
  module Dashboard
    module Workflow
      class Catalog
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
            workflow_key:,
            title: workflow_key.titleize,
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
          @class_names_by_workflow_key ||= class_names_to_keys.each_with_object(
            Hash.new { |hash, key| hash[key] = [] },
          ) do |(class_name, workflow_key), mapping|
            mapping[workflow_key] << class_name
          end
        end

        def observed_class_names_to_keys
          @observed_class_names_to_keys ||= observed_workflow_class_names_to_keys
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

        def workflow_key_from_class_name(class_name)
          return unless class_name.to_s.start_with?("Workflows::")

          class_name.demodulize.underscore
        end

        def trigger_keys_to_workflow_keys
          @trigger_keys_to_workflow_keys ||= begin
            mapping = Hash.new { |hash, key| hash[key] = [] }

            recurring_tasks.each { |task| mapping[task.trigger_key] << task.workflow_key }

            mapping.transform_values { |values| values.compact.uniq }
          end
        end
      end
    end
  end
end

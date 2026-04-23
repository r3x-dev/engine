module R3x
  module Dashboard
    module Workflow
      class RunEnqueuer
        def initialize(workflow_key:, trigger_key:)
          @workflow_key = workflow_key.to_s
          @trigger_key = trigger_key.presence&.to_s
        end

        def enqueue!
          if trigger_key.present? && recurring_task.change_detection?
            enqueue_change_detection_job
          else
            ::Dashboard::Run.enqueue_direct!(**direct_enqueue_options)
          end
        end

        private
          attr_reader :trigger_key, :workflow_key

          def enqueue_change_detection_job
            R3x::ChangeDetectionJob
              .set(job_options)
              .perform_later(workflow_key, trigger_key: trigger_key)
          end

          def direct_enqueue_options
            trigger_key.present? ? trigger_enqueue_options : manual_enqueue_options
          end

          def trigger_enqueue_options
            ::Dashboard::Run.trigger_enqueue_options_for(recurring_task) ||
              raise(KeyError, "No direct workflow enqueue target for '#{workflow_key}'")
          end

          def manual_enqueue_options
            catalog_entry = catalog.find!(workflow_key)

            ::Dashboard::Run.manual_enqueue_options_for(
              workflow_key: workflow_key,
              class_name: catalog_entry[:class_name],
              recurring_task: preferred_recurring_task,
              last_run: last_run
            ) || raise(KeyError, "No direct workflow enqueue target for '#{workflow_key}'")
          end

          def recurring_task
            @recurring_task ||= ::Dashboard::RecurringTask.find_by_workflow_and_trigger_key!(
              workflow_key: workflow_key,
              trigger_key: trigger_key
            )
          end

          def preferred_recurring_task
            @preferred_recurring_task ||= ::Dashboard::RecurringTask.preferred_for_workflow(workflow_key)
          end

          def last_run
            @last_run ||= begin
              run = Workflow::Runs.new(workflow_key: workflow_key, limit: 1).all.first
              ::Dashboard::Run.with_execution_associations.find_by(id: run[:job_id]) if run.present?
            end
          end

          def catalog
            @catalog ||= Workflow::Catalog.new
          end

          def job_options
            {
              queue: recurring_task.queue_name,
              priority: recurring_task.priority
            }.compact
          end
      end
    end
  end
end

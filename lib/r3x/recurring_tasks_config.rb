module R3x
  class RecurringTasksConfig
    extend R3x::Concerns::Logger

    class << self
      def schedule_all!
        current_keys = []
        scheduled_logs = []
        task_options = []
        stale_count = 0

        Workflow::Registry.all.each do |workflow_class|
          triggers = workflow_class.schedulable_triggers
          next if triggers.empty?

          workflow_key = workflow_class.workflow_key

          triggers.each do |trigger|
            key = namespaced_key(workflow_key, trigger)
            current_keys << key
            task_options << [ key, task_options_for(workflow_class: workflow_class, trigger: trigger) ]
          end
        end

        SolidQueue::RecurringTask.transaction do
          stale_scope = SolidQueue::RecurringTask.dynamic.where("key LIKE 'workflow:%'").where.not(key: current_keys)
          stale_count = stale_scope.count
          stale_scope.delete_all

          task_options.each do |key, options|
            task = SolidQueue::RecurringTask.dynamic.find_or_initialize_by(key: key)
            task.class_name = options[:class]
            task.arguments = options[:args]
            task.schedule = options[:schedule]
            task.queue_name = options[:queue]
            task.save!

            workflow_key, trigger_key = workflow_and_trigger_for(key)
            scheduled_logs << [ workflow_key, trigger_key, options ]
          end
        end

        scheduled_logs.each do |workflow_key, trigger_key, options|
          Rails.logger.tagged("r3x.workflow_key=#{workflow_key}", "r3x.trigger_key=#{trigger_key}") do
            logger.info "Scheduled recurring task class=#{options[:class]} schedule=#{options[:schedule]} queue=#{options[:queue]}"
          end
        end

        logger.info("Scheduled #{current_keys.size} dynamic recurring tasks stale_removed=#{stale_count}")
      rescue => e
        logger.error("Recurring task scheduling failed error_class=#{e.class} error_message=#{e.message}")
        raise
      end

      def to_h
        result = {}

        Workflow::Registry.all.each do |workflow_class|
          triggers = workflow_class.schedulable_triggers
          next if triggers.empty?

          workflow_key = workflow_class.workflow_key

          triggers.each do |trigger|
            result_key = namespaced_key(workflow_key, trigger)
            result[result_key] = task_options_for(
              workflow_class: workflow_class, trigger: trigger
            ).stringify_keys
          end
        end

        result
      end

      private

      def namespaced_key(workflow_key, trigger)
        "workflow:#{workflow_key}:#{trigger.unique_key}"
      end

      def task_options_for(workflow_class:, trigger:)
        queue_name = workflow_class.new.queue_name
        if trigger.change_detecting?
          {
            class: "R3x::ChangeDetectionJob",
            args: [ workflow_class.workflow_key, { "trigger_key" => trigger.unique_key } ],
            schedule: trigger.schedule,
            queue: queue_name
          }
        else
          {
            class: workflow_class.name,
            args: [ trigger.unique_key ],
            schedule: trigger.schedule,
            queue: queue_name
          }
        end
      end

      def workflow_and_trigger_for(key)
        _, workflow_key, *trigger_key_parts = key.split(":")
        [ workflow_key, trigger_key_parts.join(":") ]
      end
    end
  end
end

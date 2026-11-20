# frozen_string_literal: true

module R3x
  class RecurringTasksConfig
    extend R3x::Concerns::Logger

    class << self
      def schedule_all!
        tasks = []
        stale_count = 0

        Workflow::Registry.all.each do |workflow_class|
          triggers = workflow_class.schedulable_triggers
          next if triggers.empty?

          workflow_key = workflow_class.workflow_key

          triggers.each do |trigger|
            trigger_key = trigger.unique_key
            key = Workflow::RecurringTaskKey.build(workflow_key:, trigger_key:)
            tasks << [key, workflow_key, trigger_key, task_options_for(workflow_class:, trigger:)]
          end
        end

        SolidQueue::RecurringTask.transaction do
          stale_scope = SolidQueue::RecurringTask.dynamic
            .where("key LIKE ?", Workflow::RecurringTaskKey::PATTERN).where.not(key: tasks.map(&:first))
          stale_count = stale_scope.delete_all

          tasks.each do |key, _, _, options|
            task = SolidQueue::RecurringTask.dynamic.find_or_initialize_by(key:)
            task.class_name = options[:class]
            task.arguments = options[:args]
            task.schedule = options[:schedule]
            task.queue_name = options[:queue]
            task.save!
          end
        end

        tasks.each do |_, workflow_key, trigger_key, options|
          tags = [R3x::Log.tag(R3x::Log::WORKFLOW_KEY_TAG, workflow_key), R3x::Log.tag(R3x::Log::TRIGGER_KEY_TAG, trigger_key)]

          Rails.logger.tagged(*tags) do
            logger.info "Scheduled recurring task class=#{options[:class]} schedule=#{options[:schedule]} queue=#{options[:queue]}"
          end
        end

        logger.info("Scheduled #{tasks.size} dynamic recurring tasks stale_removed=#{stale_count}")
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
            result_key = Workflow::RecurringTaskKey.build(workflow_key:, trigger_key: trigger.unique_key)
            result[result_key] = task_options_for(workflow_class:, trigger:).stringify_keys
          end
        end

        result
      end

      private

      def task_options_for(workflow_class:, trigger:)
        queue_attr = workflow_class.queue_name
        queue_name = queue_attr.is_a?(Proc) ? ActiveJob::Base.default_queue_name : queue_attr

        {
          class: workflow_class.name,
          args: [trigger.unique_key],
          schedule: trigger.schedule,
          queue: queue_name,
        }
      end
    end
  end
end

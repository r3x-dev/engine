# frozen_string_literal: true

module Dashboard
  class RecurringTask < ApplicationRecord
    self.table_name = "solid_queue_recurring_tasks"

    serialize :arguments, coder: SolidQueue::RecurringTask::Arguments, default: []

    scope :workflow_tasks, -> { where("key LIKE ?", R3x::Workflow::RecurringTaskKey::PATTERN).order(:key) }
    scope :for_workflow_key, ->(workflow_key) do
      escaped_workflow_key = ActiveRecord::Base.sanitize_sql_like(workflow_key.to_s, "!")
      pattern = R3x::Workflow::RecurringTaskKey.build(workflow_key: escaped_workflow_key, trigger_key: "%")
      workflow_tasks.where("key LIKE ? ESCAPE '!'", pattern)
    end

    class << self
      def find_by_workflow_and_trigger_key(workflow_key:, trigger_key:)
        find_by(key: R3x::Workflow::RecurringTaskKey.build(workflow_key:, trigger_key:))
      end

      def find_by_workflow_and_trigger_key!(workflow_key:, trigger_key:)
        find_by!(key: R3x::Workflow::RecurringTaskKey.build(workflow_key:, trigger_key:))
      end

      def preferred_for_workflow(workflow_key)
        tasks = for_workflow_key(workflow_key).to_a

        tasks.find { |task| task.direct_workflow_class_name.present? } || tasks.first
      end
    end

    def workflow_key
      parsed_key.fetch(:workflow_key)
    end

    def trigger_key
      parsed_key.fetch(:trigger_key)
    end

    def direct_workflow_class_name
      class_name.presence
    end

    def previous_run_at(active_job_id: nil)
      executions = SolidQueue::RecurringExecution.where(task_key: key)
      if active_job_id.present?
        current_run_at = executions.joins(:job).where(SolidQueue::Job.table_name => { active_job_id: }).pick(:run_at)
        executions = executions.where("run_at < ?", current_run_at) if current_run_at
      end
      executions.maximum(:run_at)
    end

    private

    def parsed_key
      @parsed_key ||= R3x::Workflow::RecurringTaskKey.parse(key)
    end
  end
end

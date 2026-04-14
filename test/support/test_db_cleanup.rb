module TestDbCleanup
  extend self

  def clear_runtime_tables!
    attempts = 0

    begin
      SolidQueue::BlockedExecution.delete_all
      SolidQueue::ClaimedExecution.delete_all
      SolidQueue::FailedExecution.delete_all
      SolidQueue::ReadyExecution.delete_all
      SolidQueue::ScheduledExecution.delete_all
      SolidQueue::Job.delete_all
      SolidQueue::RecurringTask.delete_all
      R3x::TriggerState.delete_all
    rescue ActiveRecord::StatementTimeout => error
      attempts += 1
      raise error unless error.message.include?("database is locked") && attempts < 6

      sleep(0.02 * attempts)
      retry
    end
  end
end

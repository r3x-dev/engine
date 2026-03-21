Rails.application.config.after_initialize do
  R3x::Workflow::PackLoader.load!

  begin
    R3x::RecurringTasksConfig.schedule_all!
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    Rails.logger.warn("SolidQueue tables not available, skipping dynamic recurring task scheduling")
  end
end

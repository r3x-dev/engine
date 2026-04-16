class ApplicationJob < ActiveJob::Base
  include R3x::Concerns::Logger

  around_perform :tag_log_context

  private
    def with_log_tags(*tags, &block)
      Rails.logger.tagged(*tags.compact, &block)
    end

    def tag_log_context
      with_log_tags(*log_tags) { yield }
    end

    def log_tags
      [
        ("r3x.active_job_id=#{job_id}" if job_id.present?),
        ("r3x.run_active_job_id=#{job_id}" if job_id.present?)
      ]
    end
end

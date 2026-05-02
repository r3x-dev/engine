class ApplicationJob < ActiveJob::Base
  include R3x::StructuredLogging

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
        R3x::Log.tag(R3x::Log::RUN_ACTIVE_JOB_ID_TAG, job_id)
      ]
    end
end

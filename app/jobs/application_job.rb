# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  include R3x::StructuredLogging

  around_perform :tag_log_context

  private

  def with_log_tags(*tags, &)
    Rails.logger.tagged(*tags.compact, &)
  end

  def tag_log_context(&)
    with_log_tags(*log_tags, &)
  end

  def log_tags
    [
      R3x::Log.tag(R3x::Log::RUN_ACTIVE_JOB_ID_TAG, job_id),
    ]
  end
end

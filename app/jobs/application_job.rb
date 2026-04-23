class ApplicationJob < ActiveJob::Base
  around_perform do |job, block|
    R3x::ExecutionLogger.with(job.logger) do
      job.send(:with_log_tags, *job.send(:log_tags)) { block.call }
    end
  end

  private
    def with_log_tags(*tags, &block)
      R3x::ExecutionLogger.current.tagged(*tags.compact, &block)
    end

    def log_tags
      [
        ("r3x.run_active_job_id=#{job_id}" if job_id.present?)
      ]
    end
end

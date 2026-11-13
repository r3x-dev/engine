# frozen_string_literal: true

module Dashboard
  class DirectWorkflowEnqueuer
    include R3x::Concerns::Logger

    def self.enqueue!(...)
      new(...).enqueue!
    end

    def initialize(class_name:, arguments:, queue_name:, priority:)
      @arguments = arguments
      @class_name = class_name.to_s
      @priority = priority
      @queue_name = queue_name
    end

    def enqueue!
      enqueued_job = SolidQueue::Job.enqueue(request_job)

      Dashboard::EnqueueRequest.find(enqueued_job.id)
    rescue ActiveJob::SerializationError, ActiveRecord::ActiveRecordError, SolidQueue::Job::EnqueueError => e
      logger.error(
        "Dashboard direct enqueue failed class_name=#{class_name} " \
        "queue=#{queue_name.presence || 'default'} priority=#{priority.inspect} " \
        "error_class=#{e.class} error_message=#{e.message}",
      )

      raise Dashboard::Run::EnqueueError, "Direct workflow enqueue failed for #{class_name}: #{e.message}"
    end

    private

    attr_reader :arguments, :class_name, :priority, :queue_name

    # Deliberately bypasses constantizing workflow classes. Web pods can enqueue
    # workflow runs from persisted runtime data without loading workflow packs;
    # jobs pods resolve and execute the real class when Solid Queue performs it.
    def request_job
      job = R3x::Workflow::EnqueueJob.new(
        class_name, Dashboard::Run.normalize_arguments(arguments),
        workflow_job_id: SecureRandom.uuid, queue_name:, priority:
      )
      job.queue_name = queue_name if queue_name.present?
      job.priority = priority unless priority.nil?
      job
    end
  end
end

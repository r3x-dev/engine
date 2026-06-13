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
      enqueued_job = SolidQueue::Job.enqueue(active_job)

      Dashboard::Run.find(enqueued_job.id)
    rescue ActiveJob::SerializationError, ActiveRecord::ActiveRecordError, SolidQueue::Job::EnqueueError => e
      logger.error(
        "Dashboard direct enqueue failed class_name=#{class_name} " \
        "queue=#{queue_name.presence || 'default'} priority=#{priority.inspect} " \
        "error_class=#{e.class} error_message=#{e.message}"
      )

      raise Dashboard::Run::EnqueueError, "Direct workflow enqueue failed for #{class_name}: #{e.message}"
    end

    private

    attr_reader :arguments, :class_name, :priority, :queue_name

    # Deliberately bypasses constantizing workflow classes. Web pods can enqueue
    # workflow runs from persisted runtime data without loading workflow packs;
    # jobs pods resolve and execute the real class when Solid Queue performs it.
    def active_job
      job_class_name = class_name
      direct_job_class = Class.new(ActiveJob::Base) do
        def perform(*)
        end
      end

      direct_job_class.define_singleton_method(:name) { job_class_name }
      direct_job_class.queue_name = queue_name if queue_name.present?
      direct_job_class.priority = priority unless priority.nil?

      positional_arguments, keyword_arguments = split_arguments(arguments)

      if keyword_arguments.empty?
        direct_job_class.new(*positional_arguments)
      else
        direct_job_class.new(*positional_arguments, **keyword_arguments)
      end
    end

    def split_arguments(raw_arguments)
      positional_arguments = Array(Dashboard::Run.normalize_arguments(raw_arguments)).dup
      keyword_arguments = positional_arguments.last.is_a?(Hash) ? positional_arguments.pop.transform_keys(&:to_sym) : {}

      [ positional_arguments, keyword_arguments ]
    end
  end
end

module DashboardJobRows
  extend self

  def serialized_job_payload(job_class_name:, arguments:, queue_name: "default", priority: nil)
    build_active_job(
      job_class_name: job_class_name,
      arguments: arguments,
      queue_name: queue_name,
      priority: priority
    ).serialize
  end

  def create_job!(job_class_name:, arguments:, queue_name: "default", priority: nil, **attributes)
    SolidQueue::Job.create!(
      {
        queue_name: queue_name,
        class_name: job_class_name,
        priority: priority || 0,
        arguments: serialized_job_payload(
          job_class_name: job_class_name,
          arguments: arguments,
          queue_name: queue_name,
          priority: priority
        )
      }.merge(attributes)
    )
  end

  private

  def build_active_job(job_class_name:, arguments:, queue_name:, priority:)
    job_class = Class.new(ActiveJob::Base) do
      self.queue_name = queue_name
      self.priority = priority unless priority.nil?

      define_singleton_method(:name) { job_class_name }

      def perform(*)
      end
    end

    positional_arguments = Array(arguments).dup
    keyword_arguments = positional_arguments.last.is_a?(Hash) ? positional_arguments.pop.transform_keys(&:to_sym) : {}

    if keyword_arguments.empty?
      job_class.new(*positional_arguments)
    else
      job_class.new(*positional_arguments, **keyword_arguments)
    end
  end
end

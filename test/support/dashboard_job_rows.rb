module DashboardJobRows
  extend self

  def serialized_job_payload(job_class_name:, arguments:, queue_name: "default", priority: nil)
    Class.new(ActiveJob::Base) do
      self.queue_name = queue_name
      self.priority = priority unless priority.nil?

      define_singleton_method(:name) { job_class_name }

      def perform(*)
      end
    end.new(*arguments).serialize
  end

  def create_job!(job_class_name:, arguments:, queue_name: "default", priority: nil, **attributes)
    SolidQueue::Job.create!(
      {
        queue_name: queue_name,
        class_name: job_class_name,
        arguments: serialized_job_payload(
          job_class_name: job_class_name,
          arguments: arguments,
          queue_name: queue_name,
          priority: priority
        )
      }.merge(attributes)
    )
  end
end

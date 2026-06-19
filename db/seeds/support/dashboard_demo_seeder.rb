# frozen_string_literal: true

module Seeds
  class DashboardDemoSeeder
    DEMO_CLASS_PREFIX = "Demo::Dashboard::".freeze
    DEMO_PROCESS_PREFIX = "demo-dashboard-".freeze
    DEMO_WORKFLOW_PREFIX = "demo_".freeze

    def seed!
      clear_demo_data!

      demo_definitions.map do |definition|
        create_recurring_task!(definition)
        create_run!(definition)
      end
    end

    def print_summary(runs)
      puts "Seeded dashboard demo data for local UI review:"
      puts "  /"
      puts "  /workflow-runs"

      runs.each { |run| puts "  /workflow-runs/#{run.fetch(:job_id)}  #{run.fetch(:status)}  #{run.fetch(:workflow_key).titleize}" }
    end

    private

    def demo_definitions
      now = Time.current

      [
        {
          workflow_key: "demo_monitoring",
          class_name: "#{DEMO_CLASS_PREFIX}MonitoringJob",
          queue_name: "default",
          priority: 0,
          schedule: "15 * * * *",
          trigger_key: "schedule:hourly",
          seed_scheduled_at: now + 2.days,
          status: "finished",
          created_at: now - 18.hours,
          updated_at: now - 17.hours,
          finished_at: now - 17.hours,
          active_job_id: "demo-dashboard-finished",
        },
        {
          workflow_key: "demo_feed_watch",
          class_name: "#{DEMO_CLASS_PREFIX}FeedWatchJob",
          queue_name: "feeds",
          priority: 10,
          schedule: "*/10 * * * *",
          trigger_key: "schedule:external",
          seed_scheduled_at: now + 2.days,
          status: "failed",
          created_at: now - 3.hours,
          updated_at: now - 2.hours - 52.minutes,
          failed_at: now - 2.hours - 52.minutes,
          error: <<~ERROR.strip,
            HTTPX::TimeoutError: execution expired while polling external feed
            app/lib/r3x/client/http.rb:41:in `get'
            workflows/external/feed_watch/workflow.rb:18:in `run'
          ERROR
          active_job_id: "demo-dashboard-failed",
        },
        {
          workflow_key: "demo_invoice_dispatch",
          class_name: "#{DEMO_CLASS_PREFIX}InvoiceDispatchJob",
          queue_name: "mailers",
          priority: 5,
          schedule: "0 */6 * * *",
          trigger_key: "schedule:dispatch",
          seed_scheduled_at: now + 2.days,
          status: "running",
          created_at: now - 12.minutes,
          updated_at: now - 11.minutes,
          claimed_at: now - 11.minutes,
          active_job_id: "demo-dashboard-running",
        },
        {
          workflow_key: "demo_inventory_sync",
          class_name: "#{DEMO_CLASS_PREFIX}InventorySyncJob",
          queue_name: "low",
          priority: 20,
          schedule: "*/5 * * * *",
          trigger_key: "schedule:inventory",
          seed_scheduled_at: now + 2.days,
          status: "finished",
          created_at: now - 24.minutes,
          updated_at: now - 23.minutes,
          finished_at: now - 23.minutes,
          active_job_id: "demo-dashboard-finished-2",
        },
        {
          workflow_key: "demo_retention_cleanup",
          class_name: "#{DEMO_CLASS_PREFIX}RetentionCleanupJob",
          queue_name: "maintenance",
          priority: 30,
          schedule: "30 2 * * *",
          trigger_key: "schedule:nightly",
          status: "scheduled",
          created_at: now - 5.minutes,
          updated_at: now - 5.minutes,
          scheduled_at: now + 35.minutes,
          active_job_id: "demo-dashboard-scheduled",
        },
        {
          workflow_key: "demo_summerhouse_monitoring",
          class_name: "#{DEMO_CLASS_PREFIX}SummerhouseMonitoringJob",
          queue_name: "default",
          priority: 0,
          schedule: "0 12 * * *",
          trigger_key: "schedule:summerhouse",
          seed_scheduled_at: now + 2.days,
          active_job_id: "demo-dashboard-resumed-summerhouse",
          fragments: [
            {
              status: "finished",
              created_at: now - 4.minutes,
              updated_at: now - 3.minutes,
              finished_at: now - 3.minutes,
            },
            {
              status: "scheduled",
              created_at: now - 3.minutes,
              updated_at: now - 3.minutes,
              scheduled_at: now + 2.minutes,
              resumptions: 1,
              continuation: { "completed" => %w[check_camera_1 check_camera_2] },
            },
          ],
        },
      ]
    end

    def clear_demo_data!
      job_ids = SolidQueue::Job.where("class_name LIKE ?", "#{DEMO_CLASS_PREFIX}%").pluck(:id)

      if job_ids.any?
        SolidQueue::ClaimedExecution.where(job_id: job_ids).delete_all
        SolidQueue::FailedExecution.where(job_id: job_ids).delete_all
        SolidQueue::ReadyExecution.where(job_id: job_ids).delete_all
        SolidQueue::RecurringExecution.where(job_id: job_ids).delete_all
        SolidQueue::ScheduledExecution.where(job_id: job_ids).delete_all
        SolidQueue::Job.where(id: job_ids).delete_all
      end

      SolidQueue::RecurringTask.where("key LIKE ?", "workflow:#{DEMO_WORKFLOW_PREFIX}%").delete_all
      SolidQueue::Process.where("name LIKE ?", "#{DEMO_PROCESS_PREFIX}%").delete_all
    end

    def create_recurring_task!(definition)
      ensure_demo_job_class!(definition.fetch(:class_name))

      SolidQueue::RecurringTask.create!(
        key: recurring_task_key(definition),
        schedule: definition.fetch(:schedule),
        class_name: definition.fetch(:class_name),
        arguments: [definition.fetch(:trigger_key)],
        queue_name: definition.fetch(:queue_name),
        priority: definition.fetch(:priority),
        static: false,
      )
    end

    def ensure_demo_job_class!(class_name)
      class_name.constantize
    rescue NameError
      namespace_name, _, constant_name = class_name.rpartition("::")
      namespace = namespace_name.split("::").reduce(Object) do |parent, name|
        parent.const_defined?(name, false) ? parent.const_get(name, false) : parent.const_set(name, Module.new)
      end

      namespace.const_set(constant_name, Class.new(ActiveJob::Base) do
        def perform(*)
        end
      end)
    end

    def create_run!(definition)
      return create_fragmented_run!(definition) if definition[:fragments].present?

      job = create_job!(definition)

      apply_status!(job, definition)

      definition.merge(job_id: job.id)
    end

    def create_fragmented_run!(definition)
      fragments = definition.fetch(:fragments).map do |fragment|
        fragment_definition = definition.except(:fragments).merge(fragment)
        job = create_job!(fragment_definition)
        apply_status!(job, fragment_definition)

        fragment_definition.merge(job_id: job.id)
      end

      fragments.last.merge(
        active_job_id: definition.fetch(:active_job_id),
        workflow_key: definition.fetch(:workflow_key),
      )
    end

    def apply_status!(job, definition)
      case definition.fetch(:status)
      when "failed"
        clear_scheduled_state!(job)
        SolidQueue::FailedExecution.create!(job_id: job.id, error: definition.fetch(:error), created_at: definition.fetch(:failed_at))
      when "finished"
        clear_scheduled_state!(job)
        job.update_columns(finished_at: definition.fetch(:finished_at), updated_at: definition.fetch(:updated_at))
      when "running"
        clear_scheduled_state!(job)
        SolidQueue::ClaimedExecution.where(job_id: job.id).delete_all
        SolidQueue::ClaimedExecution.create!(
          job_id: job.id,
          process_id: create_process!(definition).id,
          created_at: definition.fetch(:claimed_at),
        )
      when "scheduled"
        SolidQueue::ScheduledExecution.where(job_id: job.id).update_all(created_at: definition.fetch(:created_at))
      else
        raise ArgumentError, "Unsupported demo status: #{definition.fetch(:status)}"
      end
    end

    def create_job!(definition)
      SolidQueue::Job.create!(
        queue_name: definition.fetch(:queue_name),
        class_name: definition.fetch(:class_name),
        priority: definition.fetch(:priority),
        active_job_id: definition.fetch(:active_job_id),
        arguments: serialized_job_payload(
          job_class_name: definition.fetch(:class_name),
          arguments: [definition.fetch(:trigger_key)],
          queue_name: definition.fetch(:queue_name),
          priority: definition.fetch(:priority),
          continuation: definition[:continuation],
          resumptions: definition[:resumptions].to_i,
        ),
        created_at: definition.fetch(:created_at),
        updated_at: definition.fetch(:updated_at),
        scheduled_at: definition[:seed_scheduled_at] || definition[:scheduled_at],
        finished_at: nil,
      )
    end

    def clear_scheduled_state!(job)
      SolidQueue::ScheduledExecution.where(job_id: job.id).delete_all
      job.update_columns(scheduled_at: nil)
    end

    def create_process!(definition)
      SolidQueue::Process.create!(
        kind: "Worker",
        last_heartbeat_at: definition.fetch(:claimed_at),
        pid: Process.pid,
        hostname: "localhost",
        metadata: "{}",
        name: "#{DEMO_PROCESS_PREFIX}#{definition.fetch(:workflow_key)}",
        created_at: definition.fetch(:claimed_at),
      )
    end

    def recurring_task_key(definition)
      "workflow:#{definition.fetch(:workflow_key)}:#{definition.fetch(:trigger_key)}"
    end

    def serialized_job_payload(job_class_name:, arguments:, queue_name:, priority:, continuation: nil, resumptions: 0)
      payload = Class.new(ActiveJob::Base) do
        self.queue_name = queue_name
        self.priority = priority unless priority.nil?

        define_singleton_method(:name) { job_class_name }

        def perform(*)
        end
      end.new(*arguments).serialize

      payload["continuation"] = continuation if continuation.present?
      payload["resumptions"] = resumptions if resumptions.positive?
      payload
    end
  end
end

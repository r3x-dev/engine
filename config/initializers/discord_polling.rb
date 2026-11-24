# frozen_string_literal: true

poller = timer = supervisor = nil
failure_pipe = nil
report_puma_failure = -> { Rails.application.config.x.discord_polling.failure_writer&.write("!") }

SolidQueue::Supervisor.before_boot do
  next unless configuration.configured_processes.any? { |process| process.kind == :scheduler }

  poller = R3x::DiscordPoller.from_registry
  next unless poller

  supervisor = self
  failure_pipe = IO.pipe
rescue StandardError
  report_puma_failure.call
  raise
end

SolidQueue.on_scheduler_start do |scheduler|
  next unless poller

  timer = Concurrent::TimerTask.new(run_now: true, execution_interval: 60, interval_type: :fixed_rate) do
    Rails.application.executor.wrap { poller.poll }
  rescue StandardError => error
    timer.shutdown
    Rails.logger.fatal(error.full_message)
    report_puma_failure.call

    # A failed child is respawned. Notify its supervisor and use the native
    # graceful shutdown path so the service exits after draining its children.
    if supervisor.standalone?
      failure_pipe.last.write("!")
      Process.kill(:TERM, scheduler.supervisor.pid)
    else
      supervisor.stop
      Thread.main.raise(error)
    end
  end
  timer.execute
end

SolidQueue.on_scheduler_stop { timer&.shutdown }

SolidQueue::Supervisor.after_shutdown do
  next unless failure_pipe

  failed = failure_pipe.first.read_nonblock(1, exception: false) == "!"
  failure_pipe.each(&:close)
  failure_pipe = poller = nil
  raise "Fatal Discord polling error" if failed
end

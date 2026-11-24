# frozen_string_literal: true

poller = timer = nil
failure_pipe = nil
report_puma_failure = -> { Rails.application.config.x.discord_polling.failure_writer&.write("!") }

SolidQueue::Supervisor.before_boot do
  next unless configuration.configured_processes.any? { |process| process.kind == :scheduler }

  poller = R3x::DiscordPoller.from_registry
  failure_pipe = IO.pipe if poller && standalone?
rescue StandardError => error
  reported_to_puma = report_puma_failure.call
  raise if standalone? || !reported_to_puma

  Rails.logger.fatal(error.full_message)
  # Stop before starting scheduler or worker threads, then let Puma shut down.
  stop
  Process.kill(:INT, Process.pid)
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
    if failure_pipe
      failure_pipe.last.write("!")
      Process.kill(:TERM, scheduler.supervisor.pid)
    else
      Process.kill(:INT, scheduler.supervisor.pid)
    end
  end
  timer.execute
end

SolidQueue.on_scheduler_stop { timer&.shutdown }

SolidQueue::Supervisor.after_shutdown do
  poller = nil
  next unless failure_pipe

  failed = failure_pipe.first.read_nonblock(1, exception: false) == "!"
  failure_pipe.each(&:close)
  failure_pipe = nil
  raise "Fatal Discord polling error" if failed
end

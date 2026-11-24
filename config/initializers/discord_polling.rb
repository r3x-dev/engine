# frozen_string_literal: true

discord_timer = nil

SolidQueue.on_scheduler_start do
  poller = R3x::DiscordPoller.from_registry
  next unless poller

  discord_timer = Concurrent::TimerTask.new(run_now: true, execution_interval: 60) do
    Rails.application.executor.wrap { poller.poll }
  end
  discord_timer.add_observer do |_, _, error|
    Rails.logger.error "Discord polling failed error_class=#{error.class} error_message=#{error.message}" if error
  end
  discord_timer.execute
end

SolidQueue.on_scheduler_stop { discord_timer&.shutdown }

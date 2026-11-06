# frozen_string_literal: true

module Workflows
  class DryRunWorkflow < R3x::Workflow::Base
    trigger :manual

    def run
      step :deliver do
        ctx.client.discord.deliver(content: "Test message")
      end

      step :acknowledge, isolated: true do
        ctx.client.miniflux.entries
        ctx.client.miniflux.update_entries(entry_ids: [1], status: "read")
      end

      thread_dry_run = Thread.new { R3x::Policy.dry_run_for(:miniflux, false) }.value # rubocop:disable ThreadSafety/NewThread -- Verify the guard reaches a real child thread.

      {
        "explicit_dry_run" => R3x::Policy.dry_run_for(:discord, false),
        "thread_dry_run"   => thread_dry_run,
      }
    end
  end
end

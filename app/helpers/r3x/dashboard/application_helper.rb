module R3x
  module Dashboard
    module ApplicationHelper
      def dashboard_health_label(health)
        health.fetch(:label)
      end

      def dashboard_status_label(status)
        {
          "blocked" => "Blocked",
          "failed" => "Failed",
          "finished" => "Success",
          "queued" => "Queued",
          "running" => "Running",
          "scheduled" => "Scheduled"
        }.fetch(status, status.to_s.humanize)
      end

      def dashboard_tone_for(value)
        {
          "blocked" => "warn",
          "failed" => "danger",
          "finished" => "ok",
          "healthy" => "ok",
          "idle" => "muted",
          "queued" => "info",
          "running" => "info",
          "scheduled" => "info",
          "trigger_error" => "danger"
        }.fetch(value, "muted")
      end

      def dashboard_relative_time(time)
        return "Never" if time.blank?

        "#{time_ago_in_words(time)} ago"
      end

      def dashboard_timestamp(time)
        return content_tag(:span, "Never", class: "muted") if time.blank?

        time_tag(
          time,
          dashboard_relative_time(time),
          datetime: time.iso8601,
          title: time.strftime("%Y-%m-%d %H:%M:%S %Z")
        )
      end

      def dashboard_trigger_label(trigger_entry)
        trigger = trigger_entry.fetch(:trigger)
        return "Manual" if trigger.manual?
        return trigger.type.to_s.humanize unless trigger.respond_to?(:cron)

        "#{trigger.type.to_s.humanize}: #{trigger.cron}"
      end

      def dashboard_workflow_link(run)
        return run.fetch(:workflow_title) unless run[:known_workflow]

        link_to run.fetch(:workflow_title), workflow_path(run.fetch(:workflow_key))
      end

      def dashboard_error_summary(text)
        text.to_s.lines.first.to_s.strip.presence || "Unknown error"
      end
    end
  end
end

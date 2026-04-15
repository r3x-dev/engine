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

        suffix = time.future? ? "from now" : "ago"
        "#{time_ago_in_words(time)} #{suffix}"
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
        mode = trigger_entry.fetch(:mode)
        cron = trigger_entry[:cron]

        return "Schedule: #{cron}" if cron.present?

        {
          "change_detecting" => "Change detection",
          "manual" => "Manual",
          "observed" => "Observed trigger"
        }.fetch(mode.to_s, mode.to_s.humanize)
      end

      def dashboard_trigger_kind(trigger_entry)
        {
          "change_detecting" => "Change detection",
          "manual" => "Manual",
          "observed" => "Observed",
          "schedule" => "Schedule",
          "scheduled" => "Schedule"
        }.fetch(trigger_entry.fetch(:mode).to_s, trigger_entry.fetch(:mode).to_s.humanize)
      end

      def dashboard_trigger_details(trigger_entry)
        trigger_entry[:cron].presence || trigger_entry[:unique_key]
      end

      def dashboard_workflow_link(run)
        return run.fetch(:workflow_title) unless run[:known_workflow]

        link_to run.fetch(:workflow_title), workflow_path(run.fetch(:workflow_key))
      end

      def dashboard_error_summary(text)
        summary = if text.is_a?(Hash)
          text["message"] || text[:message] || text["error"] || text[:error] || text.inspect
        else
          extract_error_message(text.to_s)
        end

        truncate(summary.presence || "Unknown error", length: 160, separator: " ")
      end

      def dashboard_error_body(text)
        return "No error details recorded." if text.blank?

        if text.is_a?(Hash)
          text.inspect
        else
          text.to_s
        end
      end

      def dashboard_icon(name)
        icon_name, variant = {
          alert: [ "exclamation-triangle", :outline ],
          history: [ "clock", :outline ],
          launch: [ "play", :solid ],
          logs: [ "document-text", :outline ],
          tune: [ "cog-6-tooth", :outline ],
          workflow: [ "queue-list", :outline ]
        }.fetch(name)

        content_tag(
          :span,
          raw(Heroicon::Icon.render(name: icon_name, variant: variant, options: { class: "icon" }, path_options: {})),
          class: "icon"
        )
      end

      def dashboard_icon_label(name, text)
        safe_join([ dashboard_icon(name), content_tag(:span, text) ], " ")
      end

      def dashboard_log_metadata(entry)
        [ entry[:pod_name], entry[:container_name] ].compact.join(" / ")
      end

      private
        def extract_error_message(text)
          first_line = text.lines.first.to_s.strip
          return Regexp.last_match(1) if first_line.match(/"message"\s*=>\s*"([^"]+)"/)
          return Regexp.last_match(1) if first_line.match(/"message"\s*:\s*"([^"]+)"/)

          first_line
      end
    end
  end
end

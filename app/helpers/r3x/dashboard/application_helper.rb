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

        displayed_time = dashboard_display_time(time)

        time_tag(
          displayed_time,
          dashboard_relative_time(time),
          datetime: displayed_time.iso8601,
          title: displayed_time.strftime("%Y-%m-%d %H:%M:%S %Z")
        )
      end

      def dashboard_absolute_timestamp(time)
        return content_tag(:span, "Never", class: "muted") if time.blank?

        displayed_time = dashboard_display_time(time)
        formatted_time = displayed_time.strftime("%Y-%m-%d %H:%M:%S %Z")

        time_tag(
          displayed_time,
          formatted_time,
          datetime: displayed_time.iso8601,
          title: dashboard_relative_time(time)
        )
      end

      def dashboard_log_time(time)
        return content_tag(:span, "--:--:--", class: "muted") if time.blank?

        displayed_time = dashboard_display_time(time)

        time_tag(
          displayed_time,
          displayed_time.strftime("%H:%M:%S"),
          datetime: displayed_time.iso8601,
          title: displayed_time.strftime("%Y-%m-%d %H:%M:%S %Z")
        )
      end

      def dashboard_log_level_label(level)
        level.to_s.upcase
      end

      def dashboard_log_level_tone(level)
        case level.to_s
        when "info"
          "info"
        when "warn"
          "warn"
        when "error", "fatal"
          "danger"
        else
          "muted"
        end
      end

      def dashboard_log_state_empty_message(refreshable:, empty_message:)
        return "Waiting for first log line..." if refreshable

        empty_message
      end

      def dashboard_duration(start_time, end_time = nil)
        return content_tag(:span, "Unknown", class: "muted") if start_time.blank?

        finish_time = end_time || Time.current
        total_seconds = [ (finish_time - start_time).to_i, 0 ].max

        hours = total_seconds / 3600
        minutes = (total_seconds % 3600) / 60
        seconds = total_seconds % 60

        format("%02d:%02d:%02d", hours, minutes, seconds)
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

      def dashboard_error_multiline?(text)
        dashboard_error_body(text).lines.size > 1
      end

      def dashboard_error_details_visible?(text)
        body = dashboard_error_body(text)
        body.present? && dashboard_error_summary(text) != body
      end

      def dashboard_structured_error(text)
        parsed_error =
          case text
          when Hash
            text.stringify_keys
          else
            parse_dashboard_error_text(text.to_s)
          end

        return if parsed_error.blank?

        {
          exception_class: parsed_error["exception_class"].presence || parsed_error["error_class"].presence,
          message: parsed_error["message"].presence || parsed_error["error"].presence,
          backtrace: Array(parsed_error["backtrace"] || parsed_error["trace"] || parsed_error["stack"]).compact_blank
        }.compact_blank
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

      def dashboard_run_filter_path(status:, workflow_key: nil)
        params = {}
        params[:workflow] = workflow_key if workflow_key.present?
        params[:status] = status if status.present?

        workflow_runs_path(params)
      end

      def dashboard_workflow_sort_aria(sort_key, active_sort:, active_direction:)
        return "none" unless active_sort == sort_key.to_s

        active_direction == "desc" ? "descending" : "ascending"
      end

      def dashboard_workflow_sort_link(label, sort_key, active_sort:, active_direction:)
        sort_key = sort_key.to_s
        next_direction = if active_sort == sort_key
          active_direction == "desc" ? "asc" : "desc"
        else
          Workflow::Summaries.default_direction_for(sort_key)
        end

        active = active_sort == sort_key

        link_to workflows_path(sort: sort_key, direction: next_direction, anchor: "workflows-catalog"), class: "sort-link#{' active' if active}" do
          safe_join(
            [
              content_tag(:span, label, class: "sort-label"),
              content_tag(:span, class: "sort-carets", "aria-hidden": "true") do
                safe_join(
                  [
                    content_tag(:span, "", class: "sort-caret sort-caret-up#{' active' if active && active_direction == 'asc'}"),
                    content_tag(:span, "", class: "sort-caret sort-caret-down#{' active' if active && active_direction == 'desc'}")
                  ]
                )
              end
            ]
          )
        end
      end

      private
        def dashboard_display_time(time)
          time.in_time_zone(dashboard_time_zone_name)
        end

        def dashboard_time_zone_name
          @dashboard_time_zone_name ||= begin
            timezone_name = R3x::Env.fetch("R3X_TIMEZONE")
            timezone_name.present? ? R3x::Validators::Timezone.normalize(timezone_name) : Time.zone.tzinfo.identifier
          end
        end

        def extract_error_message(text)
          first_line = text.lines.first.to_s.strip
          return Regexp.last_match(1) if first_line.match(/"message"\s*=>\s*"([^"]+)"/)
          return Regexp.last_match(1) if first_line.match(/"message"\s*:\s*"([^"]+)"/)

          first_line
        end

        def parse_dashboard_error_text(text)
          return if text.blank?

          parse_json_error_text(text) || parse_ruby_hash_error_text(text)
        end

        def parse_json_error_text(text)
          return unless text.lstrip.start_with?("{", "[")

          parsed = MultiJson.load(text)
          parsed.is_a?(Hash) ? parsed.stringify_keys : nil
        rescue MultiJson::ParseError
          nil
        end

        def parse_ruby_hash_error_text(text)
          return unless text.include?("=>")

          exception_class = extract_ruby_hash_error_value(text, "exception_class")
          message = extract_ruby_hash_error_value(text, "message")
          backtrace = extract_ruby_hash_error_array(text, "backtrace")

          {
            "exception_class" => exception_class,
            "message" => message,
            "backtrace" => backtrace
          }.compact_blank
        end

        def extract_ruby_hash_error_value(text, key)
          match = text.match(
            /"#{Regexp.escape(key)}"\s*(?:=>|:)\s*"(?<value>.*?)"\s*(?=,\s*"(?:exception_class|error_class|message|error|backtrace|trace|stack)"\s*(?:=>|:)|\s*}\z)/m
          )
          return unless match

          unescape_dashboard_error_string(match[:value])
        end

        def extract_ruby_hash_error_array(text, key)
          match = text.match(
            /"#{Regexp.escape(key)}"\s*(?:=>|:)\s*\[(?<value>.*?)\]\s*(?=,\s*"(?:exception_class|error_class|message|error|backtrace|trace|stack)"\s*(?:=>|:)|\s*}\z)/m
          )
          return [] unless match

          match[:value]
            .scan(/"((?:[^"\\]|\\.)*)"/)
            .flatten
            .map { |value| unescape_dashboard_error_string(value) }
        end

        def unescape_dashboard_error_string(value)
          MultiJson.load(%("#{value}"))
        rescue MultiJson::ParseError
          value.to_s.gsub('\"', '"').gsub("\\\\", "\\")
        end
    end
  end
end

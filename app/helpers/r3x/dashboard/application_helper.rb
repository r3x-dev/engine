# frozen_string_literal: true

module R3x
  module Dashboard
    module ApplicationHelper
      TONE_BY_STATUS = {
        "blocked"   => "warn",
        "failed"    => "danger",
        "finished"  => "ok",
        "healthy"   => "ok",
        "idle"      => "muted",
        "queued"    => "info",
        "running"   => "info",
        "scheduled" => "info",
        "sleeping"  => "info",
      }.freeze

      def dashboard_health_label(health)
        health.fetch(:label)
      end

      def dashboard_status_label(status)
        status.to_s.humanize
      end

      def dashboard_tone_for(value)
        TONE_BY_STATUS.fetch(value, "muted")
      end

      def dashboard_pill(label, tone, title: nil, class_name: nil)
        classes = ["pill", tone, class_name].compact.join(" ")
        options = { class: classes }
        options[:title] = title if title.present?

        content_tag(:span, label, options)
      end

      def dashboard_status_pill(status, error: nil)
        dashboard_pill(
          dashboard_status_label(status),
          dashboard_tone_for(status),
          title: error.present? ? dashboard_error_summary(error) : nil,
        )
      end

      def dashboard_health_pill(health)
        dashboard_pill(
          dashboard_health_label(health),
          dashboard_tone_for(health[:status]),
          title: health[:detail].present? ? dashboard_error_summary(health[:detail]) : nil,
        )
      end

      def dashboard_optional_timestamp(time, fallback:)
        time.present? ? dashboard_timestamp(time) : fallback
      end

      def dashboard_relative_time(time)
        return "Never" if time.blank?

        dashboard_timestamp_text(time)
      end

      def dashboard_timestamp(time)
        return content_tag(:span, "Never", class: "muted") if time.blank?

        displayed_time = dashboard_display_time(time)
        formatted_time = dashboard_timestamp_text(displayed_time)

        time_tag(displayed_time, formatted_time, datetime: displayed_time.iso8601, title: formatted_time)
      end

      def dashboard_absolute_timestamp(time)
        return content_tag(:span, "Never", class: "muted") if time.blank?

        displayed_time = dashboard_display_time(time)
        formatted_time = dashboard_timestamp_text(displayed_time)

        time_tag(displayed_time, formatted_time, datetime: displayed_time.iso8601, title: formatted_time)
      end

      def dashboard_log_time(time)
        return content_tag(:span, "--:--:--", class: "muted") if time.blank?

        displayed_time = dashboard_display_time(time)

        time_tag(
          displayed_time,
          displayed_time.strftime("%H:%M:%S"),
          datetime: displayed_time.iso8601,
          title: displayed_time.strftime("%Y-%m-%d %H:%M:%S %Z"),
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
        total_seconds = [(finish_time - start_time).to_i, 0].max

        hours = total_seconds / 3600
        minutes = (total_seconds % 3600) / 60
        seconds = total_seconds % 60

        format("%02d:%02d:%02d", hours, minutes, seconds)
      end

      def dashboard_trigger_label(trigger_entry)
        mode = trigger_entry.fetch(:mode)
        cron = trigger_entry[:cron]

        return "Schedule: #{cron}" if cron.present?

        { "manual" => "Manual", "observed" => "Observed trigger" }.fetch(mode.to_s, mode.to_s.humanize)
      end

      def dashboard_trigger_kind(trigger_entry)
        {
          "manual"    => "Manual",
          "observed"  => "Observed",
          "schedule"  => "Schedule",
          "scheduled" => "Schedule",
        }.fetch(trigger_entry.fetch(:mode).to_s, trigger_entry.fetch(:mode).to_s.humanize)
      end

      def dashboard_trigger_details(trigger_entry)
        visible_details = if trigger_entry[:cron].present?
          dashboard_schedule_trigger_label(trigger_entry[:cron])
        else
          dashboard_trigger_key_label(trigger_entry[:unique_key])
        end
        return visible_details if trigger_entry[:unique_key].blank?

        content_tag(:span, visible_details, title: trigger_entry[:unique_key])
      end

      def dashboard_trigger_key_label(trigger_key)
        return "manual/default" if trigger_key.blank?

        _type, details = trigger_key.to_s.split(":", 2)
        details.presence || trigger_key
      end

      def dashboard_run_trigger_label(run)
        return "manual/default" if run[:trigger_key].blank?

        if run[:trigger_schedule].present?
          dashboard_schedule_trigger_label(run[:trigger_schedule])
        else
          dashboard_trigger_key_label(run[:trigger_key])
        end
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
        dashboard_error_body(text).each_line.first(2).size > 1
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
          backtrace: Array(parsed_error["backtrace"] || parsed_error["trace"] || parsed_error["stack"]).compact_blank,
        }.compact_blank
      end

      def dashboard_icon(name)
        icon_name, variant = {
          alert: ["exclamation-triangle", :outline],
          history: ["clock", :outline],
          launch: ["play", :solid],
          logs: ["document-text", :outline],
          tune: ["cog-6-tooth", :outline],
          workflow: ["queue-list", :outline],
        }.fetch(name)

        icon_html = Heroicon::Icon.render(name: icon_name, variant:, options: { class: "icon" }, path_options: {})
        content_tag(:span, raw(icon_html), class: "icon")
      end

      def dashboard_icon_label(name, text)
        safe_join([dashboard_icon(name), content_tag(:span, text)], " ")
      end

      def dashboard_run_filter_path(status:, workflow_key: nil)
        params = {}
        params[:workflow] = workflow_key if workflow_key.present?
        params[:status] = status if status.present?

        workflow_runs_path(params)
      end

      def dashboard_workflow_sort_aria(sort_key, active_sort:, active_direction:)
        return "none" unless active_sort == sort_key.to_s

        (active_direction == "desc") ? "descending" : "ascending"
      end

      def dashboard_workflow_sort_link(label, sort_key, active_sort:, active_direction:)
        sort_key = sort_key.to_s
        next_direction = if active_sort == sort_key
          (active_direction == "desc") ? "asc" : "desc"
        else
          Workflow::Summaries.default_direction_for(sort_key)
        end

        active = active_sort == sort_key

        path = workflows_path(sort: sort_key, direction: next_direction, anchor: "workflows-catalog")
        link_to path, class: "sort-link#{" active" if active}" do
          safe_join(
            [
              content_tag(:span, label, class: "sort-label"),
              content_tag(:span, class: "sort-carets", "aria-hidden": "true") do
                safe_join(
                  [
                    content_tag(:span, "", class: "sort-caret sort-caret-up#{" active" if active && active_direction == "asc"}"),
                    content_tag(:span, "", class: "sort-caret sort-caret-down#{" active" if active && active_direction == "desc"}"),
                  ],
                )
              end,
            ],
          )
        end
      end

      private

      def dashboard_display_time(time)
        time.in_time_zone(dashboard_time_zone_name)
      end

      def dashboard_timestamp_text(time)
        dashboard_display_time(time).strftime("%d.%m.%Y %H:%M:%S %Z")
      end

      def dashboard_schedule_trigger_label(schedule)
        %(schedule:"#{schedule}")
      end

      def dashboard_time_zone_name
        @dashboard_time_zone_name ||= begin
          timezone_name = R3x::Env.fetch("R3X_TIMEZONE")
          timezone_name.present? ? R3x::Validators::Timezone.normalize(timezone_name) : Time.zone.tzinfo.identifier
        end
      end

      def extract_error_message(text)
        first_line = text.lines.first.to_s.strip
        return Regexp.last_match(1) if first_line =~ /"message"\s*=>\s*"([^"]+)"/
        return Regexp.last_match(1) if first_line =~ /"message"\s*:\s*"([^"]+)"/

        first_line
      end

      def parse_dashboard_error_text(text)
        return if text.blank?

        parse_json_error_text(text) || parse_ruby_hash_error_text(text)
      end

      def parse_json_error_text(text)
        return unless text.lstrip.start_with?("{", "[")

        parsed = MultiJSON.parse(text)
        parsed.is_a?(Hash) ? parsed.stringify_keys : nil
      rescue MultiJSON::ParseError
        nil
      end

      def parse_ruby_hash_error_text(text)
        return unless text.include?("=>")

        exception_class = extract_ruby_hash_error_value(text, "exception_class")
        message = extract_ruby_hash_error_value(text, "message")
        backtrace = extract_ruby_hash_error_array(text, "backtrace")

        { "exception_class" => exception_class, "message" => message, "backtrace" => backtrace }.compact_blank
      end

      def extract_ruby_hash_error_value(text, key)
        pattern = /
          "#{Regexp.escape(key)}"\s*(?:=>|:)\s*"(?<value>.*?)"\s*
          (?=,\s*"(?:exception_class|error_class|message|error|backtrace|trace|stack)"\s*(?:=>|:)|\s*}\z)
        /mx
        match = text.match(pattern)
        return unless match

        unescape_dashboard_error_string(match[:value])
      end

      def extract_ruby_hash_error_array(text, key)
        pattern = /
          "#{Regexp.escape(key)}"\s*(?:=>|:)\s*\[(?<value>.*?)\]\s*
          (?=,\s*"(?:exception_class|error_class|message|error|backtrace|trace|stack)"\s*(?:=>|:)|\s*}\z)
        /mx
        match = text.match(pattern)
        return [] unless match

        match[:value]
          .scan(/"((?:[^"\\]|\\.)*)"/)
          .flatten
          .map { |value| unescape_dashboard_error_string(value) }
      end

      def unescape_dashboard_error_string(value)
        MultiJSON.parse(%("#{value}"))
      rescue MultiJSON::ParseError
        value.to_s.gsub('\"', '"').gsub("\\\\", "\\")
      end
    end
  end
end

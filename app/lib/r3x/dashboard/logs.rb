# frozen_string_literal: true

module R3x
  module Dashboard
    module Logs
      extend self

      RUN_LOG_LIMIT = 150
      HIDDEN_TAG_PREFIXES = %w[r3x.].freeze
      PROVIDERS = {
        "victorialogs" => R3x::Client::VictoriaLogs,
      }.freeze

      def enabled?
        provider_name.present?
      end

      def configured?
        provider_class&.configured? || false
      end

      def run_logs(run)
        active_job_id = run[:active_job_id].presence
        return unavailable_logs unless enabled?
        return unavailable_logs if provider_class.present? && !configured?
        return error_logs(provider_name, "This run does not have an Active Job id yet.") if active_job_id.blank?

        tag = R3x::Log.tag(R3x::Log::RUN_ACTIVE_JOB_ID_TAG, active_job_id)
        query_logs(
          build_query(%(tags:"#{tag}")),
          start_at: run[:enqueued_at] || 1.hour.ago,
          end_at: run[:finished_at] || Time.current,
          limit: RUN_LOG_LIMIT,
          context: { class_name: run[:class_name] },
        )
      end

      private

      def provider_name
        R3x::Env.fetch("R3X_LOGS_PROVIDER")
      end

      def build_query(filter)
        "(#{filter}) | fields _time, kubernetes.pod_name, kubernetes.container_name, " \
          "_msg, level, tags, error_class, error_message, backtrace, exception_class, error, trace, stack"
      end

      def error_logs(provider, error)
        {
          configured: true,
          entries: [],
          error:,
          provider:,
        }
      end

      def query_logs(query, start_at:, end_at:, limit:, context: {})
        raw_entries = logs_client.query(query:, start_at:, end_at:, limit:)

        {
          configured: true,
          entries: raw_entries.filter_map { |entry| normalize_entry(entry, context:) },
          error: nil,
          provider: provider_name,
        }
      rescue => e
        error_logs(provider_name, e.message)
      end

      def logs_client
        provider_class&.new || raise(ArgumentError, "Unsupported logs provider: #{provider_name}")
      end

      def provider_class
        PROVIDERS[provider_name]
      end

      def normalize_entry(entry, context: {})
        payload = parse_message_payload(entry, context:)

        {
          backtrace: payload[:backtrace],
          container_name: entry["kubernetes.container_name"],
          error_class: payload[:error_class],
          error_message: payload[:error_message],
          level: payload.fetch(:level),
          message: payload.fetch(:message),
          pod_name: entry["kubernetes.pod_name"],
          tags: payload.fetch(:tags),
          time: parse_time(entry["_time"]),
        }
      rescue
        nil
      end

      def parse_message_payload(entry, context: {})
        if entry.key?("level")
          message, tags = extract_message_and_tags(entry["_msg"], tags: normalize_array_field(entry["tags"]), context:)
          error = normalize_error_fields(entry)

          return {
            backtrace: error&.fetch(:backtrace, nil),
            error_class: error&.fetch(:error_class, nil),
            error_message: error&.fetch(:message, nil),
            level: normalize_level(entry["level"]),
            message:,
            tags:,
          }
        end

        raw_message = entry["_msg"]
        payload = MultiJSON.parse(raw_message.to_s)
        raise ArgumentError, "Expected log payload to decode to a hash, got #{payload.class}" unless payload.is_a?(Hash)

        unless payload.key?("level") && payload.key?("message")
          message, tags = extract_message_and_tags(raw_message, context:)

          return {
            level: "unknown",
            message:,
            tags:,
          }
        end

        message, tags = extract_message_and_tags(payload["message"], tags: payload["tags"], context:)
        error = normalize_error_fields(payload)

        {
          backtrace: error&.fetch(:backtrace, nil),
          error_class: error&.fetch(:error_class, nil),
          error_message: error&.fetch(:message, nil),
          level: normalize_level(payload["level"]),
          message:,
          tags:,
        }
      rescue MultiJSON::ParseError
        message, tags = extract_message_and_tags(entry["_msg"], context:)

        {
          level: "unknown",
          message:,
          tags:,
        }
      end

      def normalize_level(value)
        level = value.to_s.downcase
        return level if %w[debug info warn error fatal unknown].include?(level)

        raise ArgumentError, "Unsupported log level: #{value.inspect}"
      end

      def extract_message_and_tags(message, tags: nil, context: {})
        visible_tags = Array(tags).map(&:to_s).reject { |tag| hidden_tag?(tag, context:) }
        message = message.to_s
        match = message.match(R3x::Log::TAG_PATTERN)
        return [message, visible_tags] unless match

        raw_tags = match[0].scan(/\[([^\]]+)\]/).flatten
        visible_tags = (visible_tags + raw_tags.reject { |tag| hidden_tag?(tag, context:) }).uniq
        stripped_message = message.delete_prefix(match[0]).strip

        [stripped_message.presence || message, visible_tags]
      end

      def hidden_tag?(tag, context: {})
        return true if HIDDEN_TAG_PREFIXES.any? { |prefix| tag.start_with?(prefix) }
        return true if context[:class_name].present? && tag == context[:class_name]

        false
      end

      def parse_time(value)
        return if value.blank?

        Time.zone.parse(value)
      rescue ArgumentError
        nil
      end

      def normalize_array_field(value)
        case value
        when nil
          []
        when Array
          value.compact_blank
        when String
          parsed = MultiJSON.parse(value)
          parsed.is_a?(Array) ? parsed.compact_blank : [value]
        else
          Array(value).compact_blank
        end
      rescue MultiJSON::ParseError
        [value]
      end

      def normalize_error_fields(fields)
        raw_error = {
          "error_class"     => fields["error_class"],
          "exception_class" => fields["exception_class"],
          "error_message"   => fields["error_message"],
          "error"           => fields["error"],
          "backtrace"       => normalize_array_field(fields["backtrace"]).presence,
          "trace"           => normalize_array_field(fields["trace"]).presence,
          "stack"           => normalize_array_field(fields["stack"]).presence,
        }.compact_blank

        return if raw_error.blank?

        R3x::ErrorDetails.new(raw_error).structured
      end

      def unavailable_logs
        {
          configured: false,
          entries: [],
          error: nil,
          provider: nil,
        }
      end
    end
  end
end

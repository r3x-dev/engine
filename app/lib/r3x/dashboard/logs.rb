# frozen_string_literal: true

module R3x
  module Dashboard
    class Logs
      RUN_LOG_LIMIT = 150
      HIDDEN_TAG_PREFIXES = %w[r3x.].freeze

      class << self
        def configured?(provider_name: current_provider_name)
          case normalize_provider_name(provider_name)
          when nil
            false
          when "victorialogs"
            R3x::Env.fetch("R3X_VICTORIA_LOGS_URL").present?
          else
            true
          end
        end

        def current_provider_name
          normalize_provider_name(R3x::Env.fetch("R3X_LOGS_PROVIDER"))
        end

        private

        def normalize_provider_name(provider_name)
          provider_name.presence
        end
      end

      def initialize(provider_name: self.class.current_provider_name, client: nil)
        @provider_name = provider_name.presence
        @client = client
      end

      def run_logs(run)
        active_job_id = run[:active_job_id].presence
        return unavailable_logs unless configured?
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

      attr_reader :client, :provider_name

      def configured?
        return true if client.present?

        self.class.configured?(provider_name:)
      end

      def build_query(filter)
        "(#{filter}) | fields _time, kubernetes.pod_name, kubernetes.container_name, " \
          "_msg, level, tags, error_class, error_message, backtrace"
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
        return client if client.present?

        @logs_client ||= case provider_name
        when "victorialogs"
          R3x::Client::VictoriaLogs.new
        else
          raise ArgumentError, "Unsupported logs provider: #{provider_name}"
        end
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

          return {
            backtrace: normalize_array_field(entry["backtrace"]).presence,
            error_class: entry["error_class"],
            error_message: entry["error_message"],
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

        {
          backtrace: normalize_array_field(payload["backtrace"]).presence,
          error_class: payload["error_class"],
          error_message: payload["error_message"],
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

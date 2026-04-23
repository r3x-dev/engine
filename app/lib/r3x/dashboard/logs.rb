module R3x
  module Dashboard
    class Logs
      RUN_LOG_LIMIT = 150
      HIDDEN_TAG_PREFIXES = %w[r3x.].freeze

      class << self
        def configured?(provider_name: current_provider_name, rails_env: Rails.env)
          case provider_name.presence
          when nil
            false
          when "victorialogs"
            R3x::Env.fetch("R3X_VICTORIA_LOGS_URL").present?
          when "file_log"
            rails_env.to_s == "development"
          else
            true
          end
        end

        def current_provider_name
          R3x::Env.fetch("R3X_LOGS_PROVIDER").presence
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

        query_logs(
          build_query(%(_msg:"r3x.run_active_job_id=#{active_job_id}")),
          start_at: run[:enqueued_at] || 1.hour.ago,
          end_at: run[:finished_at] || Time.current,
          limit: RUN_LOG_LIMIT,
          context: { class_name: run[:class_name] }
        )
      end

      private

      attr_reader :client, :provider_name

      def configured?
        return true if client.present?

        self.class.configured?(provider_name: provider_name, rails_env: Rails.env)
      end

      def build_query(filter)
        "#{filter} | fields _time, kubernetes.pod_name, kubernetes.container_name, _msg"
      end

      def error_logs(provider, error)
        {
          configured: true,
          entries: [],
          error: error,
          provider: provider
        }
      end

      def query_logs(query, start_at:, end_at:, limit:, context: {})
        raw_entries = logs_client.query(
          query: query,
          start_at: start_at,
          end_at: end_at,
          limit: limit
        )

        {
          configured: true,
          entries: raw_entries.filter_map { |entry| normalize_entry(entry, context: context) }.sort_by { |entry| entry[:time] || Time.at(0) },
          error: nil,
          provider: provider_name
        }
      rescue => e
        error_logs(provider_name, e.message)
      end

      def logs_client
        return client if client.present?

        @logs_client ||= case provider_name
        when "file_log"
          R3x::Client::FileLog.new
        when "victorialogs"
          R3x::Client::VictoriaLogs.new
        else
          raise ArgumentError, "Unsupported logs provider: #{provider_name}"
        end
      end

      def normalize_entry(entry, context: {})
        payload = parse_message_payload(entry["_msg"], context: context)

        {
          container_name: entry["kubernetes.container_name"],
          level: payload.fetch(:level),
          message: payload.fetch(:message),
          pod_name: entry["kubernetes.pod_name"],
          tags: payload.fetch(:tags),
          time: parse_time(entry["_time"])
        }
      rescue
        nil
      end

      def parse_message_payload(raw_message, context: {})
        parsed = MultiJson.load(raw_message.to_s)

        unless parsed.is_a?(Hash)
          raise ArgumentError, "Expected log payload to decode to a hash, got #{parsed.class}"
        end

        unless parsed.key?("level") && parsed.key?("message")
          message, tags = extract_message_and_tags(raw_message, context: context)

          return {
            level: "unknown",
            message: message,
            tags: tags
          }
        end

        message, tags = extract_message_and_tags(parsed["message"], tags: parsed["tags"], context: context)

        {
          level: normalize_level(parsed["level"]),
          message: message,
          tags: tags
        }
      rescue MultiJson::ParseError
        message, tags = extract_message_and_tags(raw_message, context: context)

        {
          level: "unknown",
          message: message,
          tags: tags
        }
      end

      def normalize_level(value)
        level = value.to_s.downcase
        return level if %w[debug info warn error fatal unknown].include?(level)

        raise ArgumentError, "Unsupported log level: #{value.inspect}"
      end

      def extract_message_and_tags(message, tags: nil, context: {})
        visible_tags = Array(tags).map(&:to_s).reject { |tag| hidden_tag?(tag, context: context) }
        message = message.to_s
        match = message.match(R3x::LogFormatter::TAG_PATTERN)
        return [ message, visible_tags ] unless match

        raw_tags = match[0].scan(/\[([^\]]+)\]/).flatten
        visible_tags = (visible_tags + raw_tags.reject { |tag| hidden_tag?(tag, context: context) }).uniq
        stripped_message = message.delete_prefix(match[0]).strip

        [ stripped_message.presence || message, visible_tags ]
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

      def unavailable_logs
        {
          configured: false,
          entries: [],
          error: nil,
          provider: nil
        }
      end
    end
  end
end

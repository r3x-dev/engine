module R3x
  module Dashboard
    class Logs
      RUN_LOG_LIMIT = 150
      TAG_PATTERN = /\A(?:\[(?<tag>[^\]]+)\]\s*)+/
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

          self.class.configured?(provider_name: provider_name)
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
          {
            configured: true,
            entries: logs_client.query(
              query: query,
              start_at: start_at,
              end_at: end_at,
              limit: limit
            ).map { |entry| normalize_entry(entry, context: context) }.sort_by { |entry| entry[:time] || Time.at(0) },
            error: nil,
            provider: provider_name
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
          message, tags = extract_message_and_tags(entry["_msg"], context: context)

          {
            container_name: entry["kubernetes.container_name"],
            message: message,
            pod_name: entry["kubernetes.pod_name"],
            severity: infer_severity(message, tags: tags),
            tags: tags,
            time: parse_time(entry["_time"])
          }
        end

        def infer_severity(message, tags: [])
          text = [ *Array(tags), message.to_s ].join(" ").downcase

          return "danger" if text.match?(/\b(error|failed|failure|exception|fatal|panic|alert)\b/)
          return "warn" if text.match?(/\b(warn|warning|retry|degraded|timeout)\b/)
          return "ok" if text.match?(/\b(success|completed|ok|healthy)\b/)

          "muted"
        end

        def extract_message_and_tags(message, context: {})
          message = message.to_s
          match = message.match(TAG_PATTERN)
          return [ message, [] ] unless match

          raw_tags = match[0].scan(/\[([^\]]+)\]/).flatten
          visible_tags = raw_tags.reject { |tag| hidden_tag?(tag, context: context) }
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

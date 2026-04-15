module R3x
  module Dashboard
    class Logs
      RUN_LOG_LIMIT = 150
      WORKFLOW_LOG_LIMIT = 200
      WORKFLOW_LOOKBACK = 24.hours

      class << self
        def configured?(provider_name: current_provider_name)
          case normalize_provider_name(provider_name)
          when "victorialogs"
            R3x::Env.fetch("R3X_VICTORIA_LOGS_URL").present?
          else
            false
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
          limit: RUN_LOG_LIMIT
        )
      end

      def workflow_logs(workflow_key)
        return unavailable_logs unless configured?

        query_logs(
          build_query(%(_msg:"r3x.workflow_key=#{workflow_key}")),
          start_at: WORKFLOW_LOOKBACK.ago,
          end_at: Time.current,
          limit: WORKFLOW_LOG_LIMIT
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

        def query_logs(query, start_at:, end_at:, limit:)
          {
            configured: true,
            entries: logs_client.query(
              query: query,
              start_at: start_at,
              end_at: end_at,
              limit: limit
            ).map { |entry| normalize_entry(entry) }.sort_by { |entry| entry[:time] || Time.at(0) },
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

        def normalize_entry(entry)
          {
            container_name: entry["kubernetes.container_name"],
            message: entry["_msg"].to_s,
            pod_name: entry["kubernetes.pod_name"],
            time: parse_time(entry["_time"])
          }
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

module R3x
  module Client
    class VictoriaLogs
      DEFAULT_TIMEOUT = "5s"

      def initialize(url_env: "R3X_VICTORIA_LOGS_URL")
        base_url = R3x::Env.secure_fetch(url_env, prefix: "R3X_VICTORIA_LOGS_URL")
        @client = HTTPX.with(
          timeout: { connect_timeout: 5, operation_timeout: 10 }
        )
        @base_url = base_url
      end

      def query(query:, start_at: nil, end_at: nil, limit: 100, timeout: DEFAULT_TIMEOUT)
        response = @client.post("#{@base_url}/select/logsql/query", form: query_params(
          query: query,
          start_at: start_at,
          end_at: end_at,
          limit: limit,
          timeout: timeout
        )).raise_for_status

        parse_json_lines(response.body)
      end

      private

      attr_reader :client, :base_url

      def query_params(query:, start_at:, end_at:, limit:, timeout:)
        {
          "end" => format_time(end_at),
          "limit" => limit,
          "query" => query,
          "start" => format_time(start_at),
          "timeout" => timeout
        }.compact
      end

      def format_time(value)
        return if value.blank?

        value.respond_to?(:iso8601) ? value.iso8601(6) : value.to_s
      end

      def parse_json_lines(body)
        body.to_s.each_line.filter_map do |line|
          stripped = line.strip
          next if stripped.blank?

          MultiJson.load(stripped)
        end
      end
    end
  end
end

module R3x
  module Client
    class Prometheus
      def initialize
        base_url = R3x::Env.fetch!("R3X_PROMETHEUS_URL")
        @connection = Faraday.new(url: base_url) do |f|
          f.request :json
          f.response :json
        end
      end

      def query(promql)
        response = connection.get("api/v1/query", query: promql)
        raise "Prometheus query failed: #{response.status}" unless response.success?

        Result.new(response.body["data"])
      end

      private

      attr_reader :connection
    end
  end
end

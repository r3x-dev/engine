module R3x
  module Client
    class Prometheus
      def initialize(url_env: "PROMETHEUS_URL")
        base_url = R3x::Env.secure_fetch(url_env, prefix: "PROMETHEUS_URL")
        @client = HTTPX.with({})
        @base_url = base_url
      end

      def query(promql)
        response = @client.get("#{@base_url}/api/v1/query", params: { query: promql })
        raise "Prometheus query failed: #{response.status}" unless response.status >= 200 && response.status < 300

        Result.new(response.json["data"])
      end

      private

      attr_reader :client, :base_url
    end
  end
end

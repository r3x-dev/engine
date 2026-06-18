module R3x
  module Client
    class Prometheus
      DEFAULT_URL_ENV = "PROMETHEUS_URL".freeze

      def initialize(url_env: DEFAULT_URL_ENV)
        @base_url = R3x::Env.secure_fetch(url_env, prefix: "#{DEFAULT_URL_ENV}_")
      end

      def query(promql)
        response = HTTPX.get("#{base_url}/api/v1/query", params: { query: promql }).raise_for_status
        Result.new(response.json["data"])
      end

      private

      attr_reader :base_url
    end
  end
end

require "test_helper"

module R3x
  module Client
    class PrometheusTest < ActiveSupport::TestCase
      setup do
        @original_url = ENV["PROMETHEUS_URL"]
      end

      teardown do
        ENV["PROMETHEUS_URL"] = @original_url
        WebMock.reset!
      end

      test "raises when PROMETHEUS_URL is missing" do
        ENV.delete("PROMETHEUS_URL")

        error = assert_raises(ArgumentError) do
          Prometheus.new
        end

        assert_equal "Missing PROMETHEUS_URL", error.message
      end

      test "raises when PROMETHEUS_URL is blank" do
        ENV["PROMETHEUS_URL"] = ""

        error = assert_raises(ArgumentError) do
          Prometheus.new
        end

        assert_equal "Missing PROMETHEUS_URL", error.message
      end

      test "supports custom url_env with matching prefix" do
        ENV["PROMETHEUS_URL_CUSTOM"] = "http://custom-prom.test:9090"

        stub_request(:get, "http://custom-prom.test:9090/api/v1/query")
          .with(query: { "query" => "up" })
          .to_return(
            status: 200,
            body: {
              status: "success",
              data: { resultType: "vector", result: [] }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        client = Prometheus.new(url_env: "PROMETHEUS_URL_CUSTOM")
        result = client.query("up")

        assert_equal "vector", result.result_type

        ENV.delete("PROMETHEUS_URL_CUSTOM")
      end

      test "rejects url_env that does not match prefix" do
        ENV["MY_PROM_URL"] = "http://prom.test:9090"

        error = assert_raises(ArgumentError) do
          Prometheus.new(url_env: "MY_PROM_URL")
        end

        assert_match(/must start with 'PROMETHEUS_URL'/, error.message)

        ENV.delete("MY_PROM_URL")
      end

      test "query returns result with series values" do
        ENV["PROMETHEUS_URL"] = "http://prometheus.test:9090"

        stub_request(:get, "http://prometheus.test:9090/api/v1/query")
          .with(query: { "query" => 'up{job="test"}' })
          .to_return(
            status: 200,
            body: {
              status: "success",
              data: {
                resultType: "vector",
                result: [
                  { metric: { "__name__" => "up", "job" => "test" }, value: [ 1700000000, "1" ] }
                ]
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        client = Prometheus.new
        result = client.query('up{job="test"}')

        assert_equal "vector", result.result_type
        series = result.first
        assert_equal "1", series.value
        assert_equal 1700000000, series.timestamp
        assert_equal({ "__name__" => "up", "job" => "test" }, series.metric)
      end

      test "query raises on non-success status" do
        ENV["PROMETHEUS_URL"] = "http://prometheus.test:9090"

        stub_request(:get, "http://prometheus.test:9090/api/v1/query")
          .with(query: { "query" => "up" })
          .to_return(status: 500, body: "internal error")

        assert_raises(RuntimeError) do
          Prometheus.new.query("up")
        end
      end
    end
  end
end

require "test_helper"

module R3x
  module Client
    class PrometheusTest < ActiveSupport::TestCase
      setup do
        @original_url = ENV["R3X_PROMETHEUS_URL"]
      end

      teardown do
        ENV["R3X_PROMETHEUS_URL"] = @original_url
        WebMock.reset!
      end

      test "raises when R3X_PROMETHEUS_URL is missing" do
        ENV.delete("R3X_PROMETHEUS_URL")

        error = assert_raises(ArgumentError) do
          Prometheus.new
        end

        assert_equal "Missing R3X_PROMETHEUS_URL", error.message
      end

      test "raises when R3X_PROMETHEUS_URL is blank" do
        ENV["R3X_PROMETHEUS_URL"] = ""

        error = assert_raises(ArgumentError) do
          Prometheus.new
        end

        assert_equal "Missing R3X_PROMETHEUS_URL", error.message
      end

      test "query returns result with series values" do
        ENV["R3X_PROMETHEUS_URL"] = "http://prometheus.test:9090"

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
        ENV["R3X_PROMETHEUS_URL"] = "http://prometheus.test:9090"

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

# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class HealthchecksIOResponseTest < ActiveSupport::TestCase
      setup do
        @base_url = "https://hc-ping.com/test-uuid-123"
        @client = HealthchecksIO.new(@base_url)
      end

      teardown do
        WebMock.reset!
      end

      test "success? returns true for successful response" do
        stub_request(:head, @base_url).to_return(status: 200, body: "OK")

        response = @client.ping

        assert response.success?
      end

      test "success? returns false for failed response" do
        stub_request(:head, @base_url).to_return(status: 500, body: "Error")

        assert_raises(Faraday::Error) do
          @client.ping
        end
      end

      test "status returns the HTTP status code" do
        stub_request(:head, @base_url).to_return(status: 201, body: "Created")

        response = @client.ping

        assert_equal 201, response.status
      end

      test "body returns the response body" do
        stub_request(:head, @base_url).to_return(status: 200, body: "Custom body")

        response = @client.ping

        assert_equal "Custom body", response.body
      end

      test "headers returns the response headers" do
        stub_request(:head, @base_url)
          .to_return(status: 200, body: "OK", headers: { "Content-Type" => "text/plain" })

        response = @client.ping

        assert_equal "text/plain", response.headers["Content-Type"]
      end

      test "body_limit returns integer from Ping-Body-Limit header" do
        stub_request(:head, @base_url)
          .to_return(status: 200, body: "OK", headers: { "Ping-Body-Limit" => "100000" })

        response = @client.ping

        assert_equal 100000, response.body_limit
      end

      test "body_limit returns nil when header not present" do
        stub_request(:head, @base_url).to_return(status: 200, body: "OK")

        response = @client.ping

        assert_nil response.body_limit
      end

      test "to_s returns body as string" do
        stub_request(:head, @base_url).to_return(status: 200, body: "Test body")

        response = @client.ping

        assert_equal "Test body", response.to_s
      end

      test "inspect shows status and success" do
        stub_request(:head, @base_url).to_return(status: 200, body: "OK")

        response = @client.ping

        assert_equal "#<R3x::Client::HealthchecksIO::Response status=200 success=true>", response.inspect
      end
    end
  end
end

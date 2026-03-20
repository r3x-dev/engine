# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class HealthchecksIOTest < ActiveSupport::TestCase
      setup do
        @base_url = "https://hc-ping.com/test-uuid-123"
        @client = HealthchecksIO.new(@base_url)
      end

      teardown do
        WebMock.reset!
      end

      test "run sends start ping, yields block, and sends success ping" do
        stub_request(:head, %r{#{@base_url}/start\?.*}).to_return(status: 200, body: "OK")
        stub_request(:head, %r{#{@base_url}\?.*}).to_return(status: 200, body: "OK")

        executed = false
        received_rid = nil

        @client.run do |client, rid|
          executed = true
          received_rid = rid
          assert_instance_of HealthchecksIO, client
          assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, rid)
        end

        assert executed
        assert_requested :head, %r{#{@base_url}/start\?.*}, times: 1
        assert_requested :head, %r{#{@base_url}\?.*}, times: 1
      end

      test "run sends fail ping when block raises error" do
        stub_request(:head, %r{#{@base_url}/start\?.*}).to_return(status: 200, body: "OK")
        stub_request(:post, %r{#{@base_url}/fail\?.*}).to_return(status: 200, body: "OK")

        error = assert_raises(StandardError) do
          @client.run do |client, rid|
            raise StandardError, "Test error"
          end
        end

        assert_equal "Test error", error.message
        assert_requested :head, %r{#{@base_url}/start\?.*}, times: 1
        assert_requested :post, %r{#{@base_url}/fail\?.*}, times: 1
      end

      test "run raises ArgumentError when no block given" do
        error = assert_raises(ArgumentError) do
          @client.run
        end

        assert_equal "Block required", error.message
      end

      test "ping sends success signal" do
        request = stub_request(:head, @base_url)
          .to_return(status: 200, body: "OK")

        response = @client.ping

        assert response.success?
        assert_equal 200, response.status
        assert_equal "OK", response.body
        assert_requested request
      end

      test "ping sends success signal with body" do
        request = stub_request(:post, @base_url)
          .with(body: "Custom data")
          .to_return(status: 200, body: "OK")

        response = @client.ping(body: "Custom data")

        assert response.success?
        assert_requested request
      end

      test "ping sends rid parameter" do
        rid = "123e4567-e89b-12d3-a456-426614174000"
        stub_request(:head, "#{@base_url}?rid=#{rid}").to_return(status: 200, body: "OK")

        response = @client.ping(rid: rid)

        assert response.success?
        assert_requested :head, "#{@base_url}?rid=#{rid}", times: 1
      end

      test "fail sends failure signal" do
        request = stub_request(:post, "#{@base_url}/fail")
          .to_return(status: 200, body: "OK")

        response = @client.fail

        assert response.success?
        assert_requested request
      end

      test "fail sends failure signal with body" do
        request = stub_request(:post, "#{@base_url}/fail")
          .with(body: "Error details")
          .to_return(status: 200, body: "OK")

        response = @client.fail(body: "Error details")

        assert response.success?
        assert_requested request
      end

      test "log sends log signal with array of lines" do
        request = stub_request(:post, "#{@base_url}/log")
          .with(body: "Line 1\nLine 2\nLine 3")
          .to_return(status: 200, body: "OK")

        response = @client.log(lines: [ "Line 1", "Line 2", "Line 3" ])

        assert response.success?
        assert_requested request
      end

      test "log sends log signal with string" do
        request = stub_request(:post, "#{@base_url}/log")
          .with(body: "Single log line")
          .to_return(status: 200, body: "OK")

        response = @client.log(lines: "Single log line")

        assert response.success?
        assert_requested request
      end

      test "exit_status sends exit code 0 as success" do
        request = stub_request(:head, "#{@base_url}/0")
          .to_return(status: 200, body: "OK")

        response = @client.exit_status(code: 0)

        assert response.success?
        assert_requested request
      end

      test "exit_status sends non-zero exit code as failure" do
        request = stub_request(:head, "#{@base_url}/1")
          .to_return(status: 200, body: "OK")

        response = @client.exit_status(code: 1)

        assert response.success?
        assert_requested request
      end

      test "chomps trailing slash from base_url" do
        client = HealthchecksIO.new("https://hc-ping.com/uuid/")
        request = stub_request(:head, "https://hc-ping.com/uuid")
          .to_return(status: 200, body: "OK")

        client.ping

        assert_requested request
      end
    end
  end
end

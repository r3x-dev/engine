# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class ApifyTest < ActiveSupport::TestCase
      teardown do
        WebMock.reset!
      end

      test "run_actor posts input and sends options as query params" do
        stub_request(:post, "https://api.apify.com/v2/acts/example-actor/runs")
          .with(query: { "memory" => "1024", "timeout" => "30" })
          .to_return(
            status: 200,
            body: MultiJSON.generate("data" => { "id" => "run-123" }),
            headers: { "Content-Type" => "application/json" }
          )

        result = Apify.new(api_key: "test-api-key").run_actor(
          "example-actor",
          input: { startUrls: [{ url: "https://example.com" }] },
          memory: 1024,
          timeout: 30,
          unused: nil
        )

        assert_equal({ "id" => "run-123" }, result)

        assert_requested(
          :post,
          "https://api.apify.com/v2/acts/example-actor/runs",
          query: { "memory" => "1024", "timeout" => "30" },
          headers: { "Authorization" => "Bearer test-api-key" }
        ) do |request|
          assert_equal({ "startUrls" => [{ "url" => "https://example.com" }] }, MultiJSON.parse(request.body))
        end
      end

      test "run_actor_sync_get_items posts input and returns parsed body" do
        stub_request(:post, "https://api.apify.com/v2/acts/example-actor/run-sync-get-dataset-items")
          .with(query: { "format" => "json", "clean" => "false", "limit" => "5", "fields" => "title" })
          .to_return(
            status: 200,
            body: MultiJSON.generate([{ "title" => "Hello" }]),
            headers: { "Content-Type" => "application/json" }
          )

        result = Apify.new(api_key: "test-api-key").run_actor_sync_get_items(
          "example-actor",
          input: { query: "ruby" },
          clean: false,
          limit: 5,
          fields: "title"
        )

        assert_equal([{ "title" => "Hello" }], result)

        assert_requested(
          :post,
          "https://api.apify.com/v2/acts/example-actor/run-sync-get-dataset-items",
          query: { "format" => "json", "clean" => "false", "limit" => "5", "fields" => "title" },
          headers: { "Authorization" => "Bearer test-api-key" }
        ) do |request|
          assert_equal({ "query" => "ruby" }, MultiJSON.parse(request.body))
        end
      end

      test "raw exposes configured connection" do
        client = Apify.new(api_key: "test-api-key")

        assert_instance_of HTTPX::Session, client.raw
      end

      test "context client uses default api key env" do
        with_env("APIFY_API_KEY" => "test-api-key") do
          client = R3x::Workflow::Context::Client.apify

          assert_instance_of Apify, client
        end
      end

      test "context client accepts custom api key env with apify prefix" do
        with_env("APIFY_API_KEY_CUSTOM" => "custom-api-key") do
          client = R3x::Workflow::Context::Client.apify(api_key_env: "APIFY_API_KEY_CUSTOM")

          assert_instance_of Apify, client
        end
      end

      test "context client rejects api key env outside apify prefix" do
        with_env("ACTOR_API_KEY" => "test-api-key") do
          error = assert_raises(ArgumentError) do
            R3x::Workflow::Context::Client.apify(api_key_env: "ACTOR_API_KEY")
          end

          assert_equal "Key 'ACTOR_API_KEY' must be 'APIFY_API_KEY' or start with 'APIFY_API_KEY_'", error.message
        end
      end

      test "context client raises when default api key env is missing" do
        with_env("APIFY_API_KEY" => nil) do
          error = assert_raises(ArgumentError) do
            R3x::Workflow::Context::Client.apify
          end

          assert_equal "Missing APIFY_API_KEY", error.message
        end
      end

      private

      def with_env(hash)
        originals = hash.each_with_object({}) { |(key, _), memo| memo[key] = ENV[key] }
        hash.each { |key, value| ENV[key] = value }
        yield
      ensure
        originals.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      end
    end
  end
end

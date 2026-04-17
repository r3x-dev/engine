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
            body: MultiJson.dump("data" => { "id" => "run-123" }),
            headers: { "Content-Type" => "application/json" }
          )

        result = Apify.new(api_key: "test-api-key").run_actor(
          "example-actor",
          input: { startUrls: [ { url: "https://example.com" } ] },
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
          assert_equal({ "startUrls" => [ { "url" => "https://example.com" } ] }, MultiJson.load(request.body))
        end
      end

      test "run_actor_sync_get_items posts input and returns parsed body" do
        stub_request(:post, "https://api.apify.com/v2/acts/example-actor/run-sync-get-dataset-items")
          .with(query: { "format" => "json", "clean" => "false", "limit" => "5", "fields" => "title" })
          .to_return(
            status: 200,
            body: MultiJson.dump([ { "title" => "Hello" } ]),
            headers: { "Content-Type" => "application/json" }
          )

        result = Apify.new(api_key: "test-api-key").run_actor_sync_get_items(
          "example-actor",
          input: { query: "ruby" },
          clean: false,
          limit: 5,
          fields: "title"
        )

        assert_equal([ { "title" => "Hello" } ], result)

        assert_requested(
          :post,
          "https://api.apify.com/v2/acts/example-actor/run-sync-get-dataset-items",
          query: { "format" => "json", "clean" => "false", "limit" => "5", "fields" => "title" },
          headers: { "Authorization" => "Bearer test-api-key" }
        ) do |request|
          assert_equal({ "query" => "ruby" }, MultiJson.load(request.body))
        end
      end

      test "raw exposes configured connection" do
        client = Apify.new(api_key: "test-api-key")

        assert_instance_of Faraday::Connection, client.raw
      end
    end
  end
end

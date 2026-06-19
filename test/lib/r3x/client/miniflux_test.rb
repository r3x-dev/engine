# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class MinifluxTest < ActiveSupport::TestCase
      teardown do
        WebMock.reset!
      end

      test "raises when url env is missing" do
        with_env("MINIFLUX_URL" => nil, "MINIFLUX_API_KEY" => "api-key") do
          error = assert_raises(ArgumentError) do
            Miniflux.new(url_env: "MINIFLUX_URL", api_key_env: "MINIFLUX_API_KEY")
          end

          assert_equal "Missing MINIFLUX_URL", error.message
        end
      end

      test "raises when api key env is missing" do
        with_env("MINIFLUX_URL" => "https://miniflux.test", "MINIFLUX_API_KEY" => nil) do
          error = assert_raises(ArgumentError) do
            Miniflux.new(url_env: "MINIFLUX_URL", api_key_env: "MINIFLUX_API_KEY")
          end

          assert_equal "Missing MINIFLUX_API_KEY", error.message
        end
      end

      test "rejects url env names outside miniflux prefix" do
        with_env("FEED_READER_URL" => "https://miniflux.test", "MINIFLUX_API_KEY" => "api-key") do
          error = assert_raises(ArgumentError) do
            Miniflux.new(url_env: "FEED_READER_URL", api_key_env: "MINIFLUX_API_KEY")
          end

          assert_equal "Key 'FEED_READER_URL' must be 'MINIFLUX_URL' or start with 'MINIFLUX_URL_'", error.message
        end
      end

      test "rejects api key env names outside miniflux prefix" do
        with_env("MINIFLUX_URL" => "https://miniflux.test", "FEED_READER_API_KEY" => "api-key") do
          error = assert_raises(ArgumentError) do
            Miniflux.new(url_env: "MINIFLUX_URL", api_key_env: "FEED_READER_API_KEY")
          end

          assert_equal "Key 'FEED_READER_API_KEY' must be 'MINIFLUX_API_KEY' or start with 'MINIFLUX_API_KEY_'", error.message
        end
      end

      test "entries fetches latest unread entries with defaults and auth header" do
        stub_entries_request("/v1/entries", query: {
          "status"    => "unread",
          "limit"     => "20",
          "order"     => "published_at",
          "direction" => "desc",
        })

        result = with_client_env do
          Miniflux.new(url_env: "MINIFLUX_URL", api_key_env: "MINIFLUX_API_KEY").entries
        end

        assert_equal 1, result["total"]
        assert_equal "Hello", result.dig("entries", 0, "title")
        assert_equal "preserved", result["upstream_field"]
      end

      test "entries uses default env names without constructor arguments" do
        stub_entries_request("/v1/entries", query: {
          "status"    => "unread",
          "limit"     => "20",
          "order"     => "published_at",
          "direction" => "desc",
        })

        result = with_client_env do
          Miniflux.new.entries
        end

        assert_equal 1, result["total"]
      end

      test "entries supports custom env names with miniflux prefixes" do
        stub_request(:get, "https://custom-miniflux.test/v1/entries")
          .with(
            query: {
              "status"    => "unread",
              "limit"     => "20",
              "order"     => "published_at",
              "direction" => "desc",
            },
            headers: { "X-Auth-Token" => "custom-api-key" },
          )
          .to_return(
            status: 200,
            body: MultiJSON.generate("total" => 0, "entries" => []),
            headers: { "Content-Type" => "application/json" },
          )

        result = with_env(
          "MINIFLUX_URL_CUSTOM"     => "https://custom-miniflux.test",
          "MINIFLUX_API_KEY_CUSTOM" => "custom-api-key",
        ) do
          Miniflux.new(url_env: "MINIFLUX_URL_CUSTOM", api_key_env: "MINIFLUX_API_KEY_CUSTOM").entries
        end

        assert_equal 0, result["total"]
      end

      test "entries passes explicit query params" do
        stub_entries_request("/v1/entries", query: {
          "status"    => "read",
          "limit"     => "5",
          "order"     => "id",
          "direction" => "asc",
        })

        result = with_client_env do
          Miniflux.new(url_env: "MINIFLUX_URL", api_key_env: "MINIFLUX_API_KEY").entries(
            status: "read",
            limit: 5,
            order: "id",
            direction: "asc",
          )
        end

        assert_equal 1, result["total"]
      end

      test "category_entries uses category path and query params" do
        stub_entries_request("/v1/categories/22/entries", query: {
          "status"    => "unread",
          "limit"     => "5",
          "order"     => "published_at",
          "direction" => "desc",
        })

        result = with_client_env do
          Miniflux.new(url_env: "MINIFLUX_URL", api_key_env: "MINIFLUX_API_KEY").category_entries(
            category_id: "22",
            limit: 5,
          )
        end

        assert_equal 1, result["total"]
      end

      test "entries supports passing arbitrary custom query filters" do
        stub_entries_request("/v1/entries", query: {
          "status"    => "unread",
          "limit"     => "20",
          "order"     => "published_at",
          "direction" => "desc",
          "starred"   => "true",
          "offset"    => "10",
        })

        result = with_client_env do
          Miniflux.new(url_env: "MINIFLUX_URL", api_key_env: "MINIFLUX_API_KEY").entries(
            starred: true,
            offset: 10,
          )
        end

        assert_equal 1, result["total"]
      end

      test "entries raises on non-success status" do
        stub_request(:get, "https://miniflux.test/v1/entries")
          .with(
            query: {
              "status"    => "unread",
              "limit"     => "20",
              "order"     => "published_at",
              "direction" => "desc",
            },
            headers: { "X-Auth-Token" => "api-key" },
          )
          .to_return(status: 500, body: "internal error")

        with_client_env do
          assert_raises(HTTPX::HTTPError) do
            Miniflux.new(url_env: "MINIFLUX_URL", api_key_env: "MINIFLUX_API_KEY").entries
          end
        end
      end

      test "mark_category_entries_as_read sends PUT request to category mark-all-as-read endpoint" do
        stub_request(:put, "https://miniflux.test/v1/categories/12/mark-all-as-read")
          .with(headers: { "X-Auth-Token" => "api-key" })
          .to_return(status: 204)

        result = with_client_env do
          Miniflux.new(url_env: "MINIFLUX_URL", api_key_env: "MINIFLUX_API_KEY")
            .mark_category_entries_as_read(category_id: 12)
        end

        assert result
      end

      test "context client builds miniflux client" do
        with_client_env do
          client = R3x::Workflow::Context::Client.miniflux(
            url_env: "MINIFLUX_URL",
            api_key_env: "MINIFLUX_API_KEY",
          )

          assert_instance_of Miniflux, client
        end
      end

      test "context client builds miniflux client with default env names" do
        stub_entries_request("/v1/entries", query: {
          "status"    => "unread",
          "limit"     => "20",
          "order"     => "published_at",
          "direction" => "desc",
        })

        result = with_client_env do
          R3x::Workflow::Context::Client.miniflux.entries
        end

        assert_equal 1, result["total"]
      end

      private

      def stub_entries_request(path, query:)
        stub_request(:get, "https://miniflux.test#{path}")
          .with(
            query:,
            headers: { "X-Auth-Token" => "api-key" },
          )
          .to_return(
            status: 200,
            body: MultiJSON.generate(
              "total"          => 1,
              "entries"        => [
                {
                  "id"           => 123,
                  "status"       => query.fetch("status"),
                  "published_at" => "2026-06-04T08:15:00Z",
                  "title"        => "Hello",
                  "url"          => "https://example.test/hello",
                },
              ],
              "upstream_field" => "preserved",
            ),
            headers: { "Content-Type" => "application/json" },
          )
      end

      def with_client_env(&block)
        with_env(
          "MINIFLUX_URL"     => "https://miniflux.test/",
          "MINIFLUX_API_KEY" => "api-key",
          &block
        )
      end

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

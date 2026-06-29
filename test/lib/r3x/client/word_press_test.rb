# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class WordPressTest < ActiveSupport::TestCase
      teardown do
        WebMock.reset!
      end

      test "raises ArgumentError when url is blank" do
        assert_raises(ArgumentError) do
          WordPress.new(url: "")
        end

        assert_raises(ArgumentError) do
          WordPress.new(url: nil)
        end
      end

      test "sets base_url and removes trailing slash" do
        client = WordPress.new(url: "https://wordpress.test/")

        assert_equal "https://wordpress.test", client.send(:base_url)
      end

      test "raises ArgumentError when api_path is blank" do
        assert_raises(ArgumentError) do
          WordPress.new(url: "https://wordpress.test", api_path: "")
        end
      end

      test "posts fetches posts with default per_page" do
        stub_request(:get, "https://wordpress.test/wp-json/wp/v2/posts")
          .with(query: { "per_page" => "10" })
          .to_return(
            status: 200,
            body: MultiJSON.generate([{ "id" => 1, "title" => { "rendered" => "Post 1" } }]),
            headers: { "Content-Type" => "application/json" },
          )

        client = WordPress.new(url: "https://wordpress.test")
        result = client.posts

        assert_equal 1, result.length
        assert_equal "Post 1", result.first.dig("title", "rendered")
      end

      test "posts passes custom query parameters" do
        stub_request(:get, "https://wordpress.test/wp-json/wp/v2/posts")
          .with(query: { "per_page" => "5", "categories" => "2" })
          .to_return(
            status: 200,
            body: MultiJSON.generate([]),
            headers: { "Content-Type" => "application/json" },
          )

        client = WordPress.new(url: "https://wordpress.test")
        result = client.posts(per_page: 5, categories: 2)

        assert_empty result
      end

      test "get fetches custom endpoint under custom api path" do
        stub_request(:get, "https://wordpress.test/wp-json/obs/v5/items/url/https%3A%2F%2Fwordpress.test%2Fstory")
          .with(
            query: { "include" => "body" },
            headers: { "Accept" => "*/*", "User-Agent" => "Observador/4.11.2 Android" },
          )
          .to_return(
            status: 200,
            body: MultiJSON.generate("content" => "Story body"),
            headers: { "Content-Type" => "application/json" },
          )

        client = WordPress.new(
          url: "https://wordpress.test/",
          api_path: "/wp-json/obs/v5/",
          user_agent: "Observador/4.11.2 Android",
          headers: { "Accept" => "*/*", "User-Agent" => "Ignored" },
        )
        result = client.get("/items/url/https%3A%2F%2Fwordpress.test%2Fstory", include: "body")

        assert_equal "Story body", result["content"]
      end

      test "post fetches a single post" do
        stub_request(:get, "https://wordpress.test/wp-json/wp/v2/posts/42")
          .to_return(
            status: 200,
            body: MultiJSON.generate({ "id" => 42, "title" => { "rendered" => "Single Post" } }),
            headers: { "Content-Type" => "application/json" },
          )

        client = WordPress.new(url: "https://wordpress.test")
        result = client.post(42)

        assert_equal 42, result["id"]
        assert_equal "Single Post", result.dig("title", "rendered")
      end

      test "pages fetches pages" do
        stub_request(:get, "https://wordpress.test/wp-json/wp/v2/pages")
          .with(query: { "per_page" => "10" })
          .to_return(
            status: 200,
            body: MultiJSON.generate([{ "id" => 10, "title" => { "rendered" => "Page 10" } }]),
            headers: { "Content-Type" => "application/json" },
          )

        client = WordPress.new(url: "https://wordpress.test")
        result = client.pages

        assert_equal 1, result.length
        assert_equal "Page 10", result.first.dig("title", "rendered")
      end

      test "page fetches a single page" do
        stub_request(:get, "https://wordpress.test/wp-json/wp/v2/pages/99")
          .to_return(
            status: 200,
            body: MultiJSON.generate({ "id" => 99, "title" => { "rendered" => "Single Page" } }),
            headers: { "Content-Type" => "application/json" },
          )

        client = WordPress.new(url: "https://wordpress.test")
        result = client.page(99)

        assert_equal 99, result["id"]
        assert_equal "Single Page", result.dig("title", "rendered")
      end

      test "context client builds wordpress client with direct url parameter" do
        client = R3x::Workflow::Context::Client.wordpress(url: "https://wordpress.test")

        assert_instance_of WordPress, client
        assert_equal "https://wordpress.test", client.send(:base_url)
      end

      test "context client passes wordpress options" do
        stub_request(:get, "https://wordpress.test/api/custom/items")
          .with(headers: { "Accept" => "*/*", "User-Agent" => "Custom agent" })
          .to_return(
            status: 200,
            body: MultiJSON.generate("ok" => true),
            headers: { "Content-Type" => "application/json" },
          )

        client = R3x::Workflow::Context::Client.wordpress(
          url: "https://wordpress.test",
          api_path: "api/custom",
          user_agent: "Custom agent",
          headers: { "Accept" => "*/*" },
        )

        assert client.get("items")["ok"]
      end
    end
  end
end

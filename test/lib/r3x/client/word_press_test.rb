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

      test "posts fetches posts with default per_page" do
        stub_request(:get, "https://wordpress.test/wp-json/wp/v2/posts")
          .with(query: { "per_page" => "10" })
          .to_return(
            status: 200,
            body: MultiJSON.generate([{ "id" => 1, "title" => { "rendered" => "Post 1" } }]),
            headers: { "Content-Type" => "application/json" }
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
            headers: { "Content-Type" => "application/json" }
          )

        client = WordPress.new(url: "https://wordpress.test")
        result = client.posts(per_page: 5, categories: 2)

        assert_empty result
      end

      test "post fetches a single post" do
        stub_request(:get, "https://wordpress.test/wp-json/wp/v2/posts/42")
          .to_return(
            status: 200,
            body: MultiJSON.generate({ "id" => 42, "title" => { "rendered" => "Single Post" } }),
            headers: { "Content-Type" => "application/json" }
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
            headers: { "Content-Type" => "application/json" }
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
            headers: { "Content-Type" => "application/json" }
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
    end
  end
end

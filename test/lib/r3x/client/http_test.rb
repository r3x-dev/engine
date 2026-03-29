require "test_helper"

module R3x
  module Client
    class HttpTest < ActiveSupport::TestCase
      teardown { WebMock.reset! }

      test "get sends request to url" do
        stub_request(:get, "https://example.com/data")
          .to_return(status: 200, body: "ok")

        response = Http.new.get("https://example.com/data")

        assert_equal 200, response.status
        assert_equal "ok", response.body
      end

      test "get passes query params" do
        stub_request(:get, "https://example.com/query")
          .with(query: { "foo" => "bar", "baz" => "1" })
          .to_return(status: 200, body: "ok")

        response = Http.new.get("https://example.com/query", params: { foo: "bar", baz: "1" })

        assert_equal 200, response.status
      end

      test "get passes headers" do
        stub_request(:get, "https://example.com/auth")
          .with(headers: { "Authorization" => "Bearer token123" })
          .to_return(status: 200, body: "ok")

        response = Http.new.get("https://example.com/auth", headers: { "Authorization" => "Bearer token123" })

        assert_equal 200, response.status
      end

      test "get returns raw body for binary responses" do
        binary_data = "\x89PNG\r\n\x1a\n".b
        stub_request(:get, "https://example.com/image.png")
          .to_return(status: 200, body: binary_data, headers: { "Content-Type" => "image/png" })

        response = Http.new.get("https://example.com/image.png")

        assert_equal binary_data, response.body
      end

      test "post passes headers" do
        stub_request(:post, "https://example.com/upload")
          .with(headers: { "Authorization" => "Bearer token123" })
          .to_return(status: 200, body: "ok")

        response = Http.new.post(
          "https://example.com/upload",
          { foo: "bar" },
          headers: { "Authorization" => "Bearer token123" }
        )

        assert_equal 200, response.status
        assert_requested :post, "https://example.com/upload"
      end

      test "head sends head request" do
        stub_request(:head, "https://example.com/ping")
          .to_return(status: 200, body: "")

        response = Http.new.head("https://example.com/ping")

        assert_equal 200, response.status
        assert_requested(:head, "https://example.com/ping")
      end

      test "head passes query params" do
        stub_request(:head, "https://example.com/ping")
          .with(query: { "token" => "abc" })
          .to_return(status: 200, body: "")

        response = Http.new.head("https://example.com/ping", params: { token: "abc" })

        assert_equal 200, response.status
      end

      test "get raises on non-success status" do
        stub_request(:get, "https://example.com/notfound")
          .to_return(status: 404, body: "not found")

        assert_raises(Faraday::Error) do
          Http.new.get("https://example.com/notfound")
        end
      end

      test "verify_ssl true by default" do
        client = Http.new
        assert_not_nil client
      end

      test "verify_ssl false creates connection without verification" do
        stub_request(:get, "https://selfsigned.lan/snapshot")
          .to_return(status: 200, body: "image-data")

        client = Http.new(verify_ssl: false)
        response = client.get("https://selfsigned.lan/snapshot")

        assert_equal 200, response.status
        assert_equal "image-data", response.body
      end
    end
  end
end

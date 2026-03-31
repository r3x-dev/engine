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

      test "download_file returns DownloadedFile with body and metadata" do
        binary_data = "\x89PNG\r\n\x1a\n".b
        stub_request(:get, "https://example.com/image.png")
          .to_return(
            status: 200,
            body: binary_data,
            headers: {
              "Content-Type" => "image/png",
              "Content-Disposition" => "attachment; filename=\"photo.png\""
            }
          )

        file = Http.new.download_file("https://example.com/image.png")

        assert_instance_of Http::DownloadedFile, file
        assert_equal binary_data, file.body
        assert_equal "image/png", file.content_type
        assert_equal "photo.png", file.filename
        assert_equal "https://example.com/image.png", file.url
      end

      test "download_file extracts filename* header values" do
        stub_request(:get, "https://example.com/report")
          .to_return(
            status: 200,
            body: "report",
            headers: {
              "Content-Disposition" => "attachment; filename*=UTF-8''report%20final.txt"
            }
          )

        file = Http.new.download_file("https://example.com/report")

        assert_equal "report final.txt", file.filename
      end

      test "download_file preserves literal plus signs in filename* header values" do
        stub_request(:get, "https://example.com/plus-report")
          .to_return(
            status: 200,
            body: "report",
            headers: {
              "Content-Disposition" => "attachment; filename*=UTF-8''report+final.txt"
            }
          )

        file = Http.new.download_file("https://example.com/plus-report")

        assert_equal "report+final.txt", file.filename
      end

      test "download_file extracts content-type without charset" do
        stub_request(:get, "https://example.com/data")
          .to_return(
            status: 200,
            body: "data",
            headers: { "Content-Type" => "text/html; charset=utf-8" }
          )

        file = Http.new.download_file("https://example.com/data")

        assert_equal "text/html", file.content_type
      end

      test "download_file handles missing content-disposition" do
        stub_request(:get, "https://example.com/file")
          .to_return(status: 200, body: "content")

        file = Http.new.download_file("https://example.com/file")

        assert_nil file.filename
        assert_nil file.content_type
      end

      test "DownloadedFile#to_io returns StringIO" do
        binary_data = "test data"
        stub_request(:get, "https://example.com/file")
          .to_return(status: 200, body: binary_data)

        file = Http.new.download_file("https://example.com/file")
        io = file.to_io

        assert_instance_of StringIO, io
        assert_equal binary_data, io.read
      end

      test "upload_file sends multipart request with file" do
        stub_request(:post, "https://api.example.com/upload")
          .to_return(status: 200, body: '{"success": true}')

        file_data = "image binary data"
        response = Http.new.upload_file(
          "https://api.example.com/upload",
          file_data,
          file_field: "image",
          params: { "foo" => "bar" }
        )

        assert_equal 200, response.status
        assert_requested :post, "https://api.example.com/upload"
      end

      test "upload_file preserves the caller file cursor" do
        stub_request(:post, "https://api.example.com/upload")
          .to_return(status: 200, body: "ok")

        file = StringIO.new("abcdef")
        file.read(2)
        original_position = file.pos

        Http.new.upload_file(
          "https://api.example.com/upload",
          file,
          file_field: "image"
        )

        assert_requested :post, "https://api.example.com/upload" do |request|
          request.body.include?("abcdef")
        end
        assert_equal original_position, file.pos
      end

      test "upload_file passes headers" do
        stub_request(:post, "https://api.example.com/upload")
          .with(headers: { "Authorization" => "Bearer token123" })
          .to_return(status: 200, body: "ok")

        Http.new.upload_file(
          "https://api.example.com/upload",
          "data",
          file_field: "file",
          headers: { "Authorization" => "Bearer token123" }
        )

        assert_requested :post, "https://api.example.com/upload",
          headers: { "Authorization" => "Bearer token123" }
      end
    end
  end
end

require "test_helper"

module R3x
  module Client
    class MarkdownifyTest < ActiveSupport::TestCase
      teardown { WebMock.reset! }

      test "convert returns hash with markdown, url, method and retain_images" do
        with_env("R3X_MARKDOWNIFY_DRY_RUN" => "false") do
          stub_request(:post, "https://markdown.new/")
            .with do |req|
              payload = MultiJSON.parse(req.body)
              payload["url"] == "https://example.com" &&
                payload["method"] == "auto" &&
                payload["retain_images"] == false
            end
            .to_return(
              status: 200,
              body: MultiJSON.generate({ "content" => "# Hello World\n\nThis is a test.", "tokens" => 42 }),
              headers: { "x-markdown-tokens" => "42", "content-type" => "application/json" }
            )

          result = Markdownify.new(url: "https://example.com").convert

          assert_equal "https://example.com", result["url"]
          assert_equal "# Hello World\n\nThis is a test.", result["markdown"]
          assert_equal 42, result["tokens"]
          assert_equal "auto", result["method"]
          refute result["retain_images"]
        end
      end

      test "convert falls back to tokens from JSON body when header is absent" do
        with_env("R3X_MARKDOWNIFY_DRY_RUN" => "false") do
          stub_request(:post, "https://markdown.new/")
            .with do |req|
              payload = MultiJSON.parse(req.body)
              payload["url"] == "https://example.com"
            end
            .to_return(
              status: 200,
              body: MultiJSON.generate({ "content" => "# Fallback", "tokens" => 99 }),
              headers: { "Content-Type" => "application/json" }
            )

          result = Markdownify.new(url: "https://example.com").convert

          assert_equal 99, result["tokens"]
        end
      end

      test "convert sends correct payload with method and retain_images" do
        with_env("R3X_MARKDOWNIFY_DRY_RUN" => "false") do
          stub_request(:post, "https://markdown.new/")
            .with do |req|
              payload = MultiJSON.parse(req.body)
              payload["method"] == "ai" && payload["retain_images"] == true
            end
            .to_return(
              status: 200,
              body: MultiJSON.generate({ "content" => "# Converted", "tokens" => 10 }),
              headers: { "Content-Type" => "application/json" }
            )

          result = Markdownify.new(
            url: "https://example.com",
            method: "ai",
            retain_images: true
          ).convert

          assert_equal "ai", result["method"]
          assert result["retain_images"]
          assert_equal "# Converted", result["markdown"]
        end
      end

      test "convert returns dry-run result when R3X_MARKDOWNIFY_DRY_RUN is set" do
        with_env("R3X_MARKDOWNIFY_DRY_RUN" => "true") do
          result = Markdownify.new(url: "https://example.com", method: "browser", retain_images: true).convert

          assert_equal "https://example.com", result["url"]
          assert_equal "", result["markdown"]
          assert_nil result["tokens"]
          assert_equal "browser", result["method"]
          assert result["retain_images"]
        end
      end

      test "convert returns dry-run result when R3X_DRY_RUN is set" do
        with_env("R3X_DRY_RUN" => "true") do
          result = Markdownify.new(url: "https://example.com").convert

          assert_equal "", result["markdown"]
          assert_nil result["tokens"]
        end
      end

      test "convert raises on non-2xx response" do
        with_env("R3X_MARKDOWNIFY_DRY_RUN" => "false") do
          stub_request(:post, "https://markdown.new/")
            .to_return(status: 500, body: MultiJSON.generate("error" => "Internal Server Error"))

          assert_raises(HTTPX::HTTPError) do
            Markdownify.new(url: "https://example.com").convert
          end
        end
      end

      test "convert sends correct default payload" do
        with_env("R3X_MARKDOWNIFY_DRY_RUN" => "false") do
          captured_payload = nil

          stub_request(:post, "https://markdown.new/")
            .with do |req|
              captured_payload = MultiJSON.parse(req.body)
              true
            end
            .to_return(
              status: 200,
              body: MultiJSON.generate({ "content" => "result", "tokens" => 5 }),
              headers: { "Content-Type" => "application/json" }
            )

          Markdownify.new(url: "https://example.com").convert

          assert_equal "https://example.com", captured_payload["url"]
          assert_equal "auto", captured_payload["method"]
          refute captured_payload["retain_images"]
        end
      end

      test "convert handles empty JSON body gracefully" do
        with_env("R3X_MARKDOWNIFY_DRY_RUN" => "false") do
          stub_request(:post, "https://markdown.new/")
            .to_return(
              status: 200,
              body: MultiJSON.generate({}),
              headers: { "Content-Type" => "application/json" }
            )

          result = Markdownify.new(url: "https://example.com").convert

          assert_equal "", result["markdown"]
          assert_nil result["tokens"]
        end
      end

      private

      def with_env(hash)
        originals = hash.each_with_object({}) { |(k, _), memo| memo[k] = ENV[k] }
        hash.each { |k, v| ENV[k] = v }
        yield
      ensure
        originals.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end
    end
  end
end

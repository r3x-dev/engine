# frozen_string_literal: true

module R3x
  module Client
    # Client for the markdown.new API — converts any public URL into clean,
    # AI-ready Markdown. No authentication required; the service is free with
    # a fair-usage limit of 500 requests per day per IP.
    #
    # @see https://markdown.new/
    #
    # @example Direct usage (full response with metadata)
    #   client = R3x::Client::Markdownify.new(url: "https://example.com")
    #   result = client.convert
    #   # => { "url" => "https://example.com",
    #   #      "markdown" => "# Hello World\n\n...",
    #   #      "tokens" => 42, "method" => "auto", "retain_images" => false }
    #
    # @example Through workflow context (markdown string only)
    #   ctx.client.markdownify(url: "https://example.com")
    #   # => "# Hello World\n\n..."
    #
    # @example With explicit conversion method
    #   client = R3x::Client::Markdownify.new(
    #     url: "https://example.com",
    #     method: "browser",
    #     retain_images: true
    #   )
    #   result = client.convert
    #
    # @example Dry-run mode (skips the API call, logs intent)
    #   Set R3X_MARKDOWNIFY_DRY_RUN=true or R3X_DRY_RUN=true.
    class Markdownify
      include R3x::Concerns::Logger

      # @return [String] default conversion method when none is specified
      DEFAULT_METHOD = "auto"

      # @param url [String] the public URL to convert to Markdown
      # @param method [String] conversion strategy — "auto", "ai", or "browser"
      #   "auto" tries native Markdown first, then Workers AI, then browser
      #   rendering (fastest-first fallback). "ai" forces Workers AI.
      #   "browser" forces headless browser rendering for JS-heavy pages.
      # @param retain_images [Boolean] whether to include images in the output
      def initialize(url:, method: DEFAULT_METHOD, retain_images: false)
        raise ArgumentError, "URL is required" if url.blank?

        @url = url
        @method = method
        @retain_images = retain_images
      end

      # Converts the URL to Markdown via the markdown.new API.
      #
      # @return [Hash] result hash with keys:
      #   "url"         [String]  the URL that was requested
      #   "markdown"    [String]  the converted Markdown (empty in dry-run)
      #   "tokens"      [Integer, nil] estimated token count from the
      #                 x-markdown-tokens header, falling back to JSON body
      #   "method"      [String]  conversion method used
      #   "retain_images" [Boolean] whether images were requested
      def convert
        if R3x::Policy.dry_run_for(:markdownify)
          logger.info "[DRY-RUN] markdownify url=#{@url} method=#{@method}"

          return dry_run_result
        end

        response = connection.post("https://markdown.new/", json: { "url" => @url, "method" => @method, "retain_images" => @retain_images }).raise_for_status

        parsed = MultiJSON.parse(response.body.to_s)

        {
          "url" => @url,
          "markdown" => parsed["content"] || "",
          "tokens" => response.headers["x-markdown-tokens"]&.to_i || parsed["tokens"],
          "method" => @method,
          "retain_images" => @retain_images
        }
      end

      private

      attr_reader :url, :method, :retain_images

      def dry_run_result
        {
          "url" => @url,
          "markdown" => "",
          "tokens" => nil,
          "method" => @method,
          "retain_images" => @retain_images
        }
      end

      def connection
        HTTPX.with(timeout: { connect_timeout: 5, operation_timeout: 30 })
      end
    end
  end
end

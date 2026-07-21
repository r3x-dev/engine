# frozen_string_literal: true

module R3x
  module Client
    class WordPress
      API_PATH = "/wp-json/wp/v2"

      def initialize(url:, api_path: API_PATH, user_agent: nil, headers: {})
        raise ArgumentError, "url is required" if url.blank?
        raise ArgumentError, "api_path is required" if api_path.blank?

        @base_url = url.delete_suffix("/")
        @api_path = normalize_path(api_path).delete_suffix("/")
        request_headers = headers.to_h
        request_headers = request_headers.merge("User-Agent" => user_agent) if user_agent.present?
        @connection = HTTPX.with(headers: request_headers)
      end

      # GET /wp-json/wp/v2/posts
      def posts(per_page: 10, **params)
        get("/posts", per_page:, **params)
      end

      # GET /wp-json/wp/v2/posts/{id}
      def post(id)
        get("/posts/#{Integer(id)}")
      end

      # GET /wp-json/wp/v2/pages
      def pages(per_page: 10, **params)
        get("/pages", per_page:, **params)
      end

      # GET /wp-json/wp/v2/pages/{id}
      def page(id)
        get("/pages/#{Integer(id)}")
      end

      def get(path, **params)
        connection.get("#{base_url}#{api_path}#{normalize_path(path)}", params:)
                  .raise_for_status
                  .json
      end

      private

      attr_reader :base_url, :api_path, :connection

      def normalize_path(path)
        "/#{path.to_s.delete_prefix("/")}"
      end
    end
  end
end

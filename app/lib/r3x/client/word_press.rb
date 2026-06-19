# frozen_string_literal: true

module R3x
  module Client
    class WordPress
      API_PATH = "/wp-json/wp/v2"

      def initialize(url:)
        raise ArgumentError, "url is required" if url.blank?

        @base_url = url.delete_suffix("/")
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

      private

      attr_reader :base_url

      def get(path, **params)
        HTTPX.get("#{base_url}#{API_PATH}#{path}", params:)
             .raise_for_status
             .json
      end
    end
  end
end

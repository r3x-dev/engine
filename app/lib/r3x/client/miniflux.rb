# frozen_string_literal: true

module R3x
  module Client
    # Client for the Miniflux REST API.
    #
    # Endpoints, request parameters, and HTTP methods are implemented according
    # to the official Miniflux API documentation:
    # See https://miniflux.app/docs/api.html
    class Miniflux
      DEFAULT_STATUS = "unread"
      DEFAULT_LIMIT = 20
      DEFAULT_ORDER = "published_at"
      DEFAULT_DIRECTION = "desc"

      def initialize(url_env:, api_key_env:)
        @base_url = R3x::Env.secure_fetch(url_env, prefix: "MINIFLUX_URL").delete_suffix("/")
        @api_key = R3x::Env.secure_fetch(api_key_env, prefix: "MINIFLUX_API_KEY")
      end

      # GET /v1/entries
      # See https://miniflux.app/docs/api.html#endpoint-get-entries
      def entries(status: DEFAULT_STATUS, limit: DEFAULT_LIMIT, order: DEFAULT_ORDER, direction: DEFAULT_DIRECTION, **filters)
        get("/v1/entries", status:, limit:, order:, direction:, **filters)
      end

      # GET /v1/categories/{categoryID}/entries
      # See https://miniflux.app/docs/api.html#endpoint-get-category-entries
      def category_entries(category_id:, status: DEFAULT_STATUS, limit: DEFAULT_LIMIT, order: DEFAULT_ORDER, direction: DEFAULT_DIRECTION, **filters)
        get("/v1/categories/#{Integer(category_id)}/entries", status:, limit:, order:, direction:, **filters)
      end

      # PUT /v1/categories/{categoryID}/mark-all-as-read
      # See https://miniflux.app/docs/api.html#endpoint-mark-category-entries-as-read
      def mark_category_entries_as_read(category_id:)
        put("/v1/categories/#{Integer(category_id)}/mark-all-as-read")
      end

      private

      attr_reader :base_url, :api_key

      def get(path, **params)
        response = connection.get("#{base_url}#{path}", params:).raise_for_status

        MultiJSON.parse(response.body.to_s)
      end

      def put(path)
        connection.put("#{base_url}#{path}").raise_for_status
        true
      end

      def connection
        @connection ||= HTTPX.with(headers: { "X-Auth-Token" => api_key })
      end
    end
  end
end

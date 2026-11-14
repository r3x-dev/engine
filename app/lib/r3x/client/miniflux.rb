# frozen_string_literal: true

module R3x
  module Client
    # Client for the Miniflux REST API.
    #
    # Endpoints, request parameters, and HTTP methods are implemented according
    # to the official Miniflux API documentation:
    # See https://miniflux.app/docs/api.html
    class Miniflux
      include R3x::Concerns::Logger

      DEFAULT_URL_ENV = "MINIFLUX_URL"
      DEFAULT_API_KEY_ENV = "MINIFLUX_API_KEY"
      API_PREFIX = "/v1"

      DEFAULT_STATUS = "unread"
      DEFAULT_LIMIT = 20
      DEFAULT_ORDER = "published_at"
      DEFAULT_DIRECTION = "desc"

      def initialize(url_env: DEFAULT_URL_ENV, api_key_env: DEFAULT_API_KEY_ENV)
        @base_url = R3x::Env.secure_fetch(url_env, prefix: "#{DEFAULT_URL_ENV}_").delete_suffix("/") + API_PREFIX
        api_key = R3x::Env.secure_fetch(api_key_env, prefix: "#{DEFAULT_API_KEY_ENV}_")
        @connection = HTTPX.with(headers: { "X-Auth-Token" => api_key })
      end

      # GET /v1/entries
      # See https://miniflux.app/docs/api.html#endpoint-get-entries
      def entries(status: DEFAULT_STATUS, limit: DEFAULT_LIMIT, order: DEFAULT_ORDER, direction: DEFAULT_DIRECTION, **filters)
        get("/entries", status:, limit:, order:, direction:, **filters)
      end

      # GET /v1/categories/{categoryID}/entries
      # See https://miniflux.app/docs/api.html#endpoint-get-category-entries
      def category_entries(
        category_id:, status: DEFAULT_STATUS, limit: DEFAULT_LIMIT,
        order: DEFAULT_ORDER, direction: DEFAULT_DIRECTION, **filters
      )
        get("/categories/#{Integer(category_id)}/entries", status:, limit:, order:, direction:, **filters)
      end

      # PUT /v1/feeds/{feedID}/refresh
      # See https://miniflux.app/docs/api.html#endpoint-refresh-feed
      def refresh_feed(feed_id:)
        put("/feeds/#{Integer(feed_id)}/refresh")
      end

      # PUT /v1/categories/{categoryID}/mark-all-as-read
      # See https://miniflux.app/docs/api.html#endpoint-mark-category-entries-as-read
      def mark_category_entries_as_read(category_id:)
        put("/categories/#{Integer(category_id)}/mark-all-as-read")
      end

      # PUT /v1/entries
      # See https://miniflux.app/docs/api.html#endpoint-update-entries
      def update_entries(entry_ids:, status: nil, starred: nil)
        ids = Array(entry_ids).map { |id| Integer(id) }
        raise ArgumentError, "entry_ids must not be empty" if ids.empty?
        raise ArgumentError, "status or starred is required" if status.nil? && starred.nil?

        # @type var payload: Hash[Symbol, untyped]
        payload = { entry_ids: ids }
        payload[:status] = status if status.present?
        payload[:starred] = starred unless starred.nil?

        put("/entries", json: payload)
      end

      private

      attr_reader :base_url, :connection

      def get(path, **params)
        connection.get("#{base_url}#{path}", params: params.compact).raise_for_status.json
      end

      def put(path, json: nil)
        if R3x::Policy.dry_run_for(:miniflux)
          logger.info "[DRY-RUN] method=PUT path=#{API_PREFIX}#{path}"
          return false
        end

        response = json.nil? ? connection.put("#{base_url}#{path}") : connection.put("#{base_url}#{path}", json:)
        response.raise_for_status
        true
      end
    end
  end
end

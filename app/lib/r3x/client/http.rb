module R3x
  module Client
    class Http
      def initialize(verify_ssl: true, timeout: 10)
        @connection = Faraday.new(ssl: { verify: verify_ssl }, request: { timeout: timeout }) do |f|
          f.response :raise_error
        end
      end

      def get(url, params: {}, headers: {})
        connection.get(url, params, headers)
      end

      def head(url, params: {}, headers: {})
        connection.head(url, params, headers)
      end

      def post(url, payload, headers: {})
        connection.post(url, payload, headers)
      end

      private

      attr_reader :connection
    end
  end
end

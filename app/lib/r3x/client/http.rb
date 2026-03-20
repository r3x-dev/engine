module R3x
  module Client
    class Http
      def initialize(verify_ssl: true)
        @connection = Faraday.new(ssl: { verify: verify_ssl }) do |f|
          f.response :raise_error
        end
      end

      def get(url, params: {}, headers: {})
        connection.get(url, params, headers)
      end

      def head(url, params: {}, headers: {})
        connection.head(url, params, headers)
      end

      def post(url, payload)
        connection.post(url, payload)
      end

      private

      attr_reader :connection
    end
  end
end

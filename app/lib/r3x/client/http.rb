module R3x
  module Client
    class Http
      def initialize
        @connection = Faraday.new
      end

      def get(url)
        connection.get(url).body
      end

      private

      attr_reader :connection
    end
  end
end

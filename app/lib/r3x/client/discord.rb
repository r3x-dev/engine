# frozen_string_literal: true

module R3x
  module Client
    class Discord
      include R3x::Concerns::Logger

      def initialize(webhook_url:)
        @webhook_url = webhook_url
      end

      def deliver(content:)
        connection.post(webhook_url, { "content" => content })

        { "mode" => "real", "content" => content }
      end

      private

      attr_reader :webhook_url

      def connection
        Faraday.new do |f|
          f.request :json
          f.response :raise_error
        end
      end
    end
  end
end

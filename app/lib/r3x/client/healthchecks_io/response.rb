# frozen_string_literal: true

module R3x
  module Client
    class HealthchecksIO
      class Response
        def initialize(faraday_response)
          @response = faraday_response
        end

        def success?
          response.success?
        end

        def status
          response.status
        end

        def body
          response.body
        end

        def headers
          response.headers
        end

        # The Ping-Body-Limit header value from Healthchecks.io.
        # Indicates the maximum request body size the server accepts.
        #
        # @return [Integer, nil] The body limit in bytes, or nil if header not present
        def body_limit
          headers["Ping-Body-Limit"]&.to_i
        end

        def to_s
          body.to_s
        end

        def inspect
          "#<#{self.class.name} status=#{status} success=#{success?}>"
        end

        private

        attr_reader :response
      end
    end
  end
end

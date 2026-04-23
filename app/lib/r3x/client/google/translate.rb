# frozen_string_literal: true

module R3x
  module Client
    module Google
      class Translate
        API_URL = "https://translation.googleapis.com/language/translate/v2"

        def initialize(project:)
          @project = project
        end

        def translate(text, to:, from: nil, format: "text")
          input = text.to_s
          return input if input.empty?

          response = connection.post(API_URL, request_body(input, to: to, from: from, format: format), authorization_header)
          translation = Array(response.body.dig("data", "translations")).first ||
            raise(ArgumentError, "Missing translations in Google Translate response")
          translation.fetch("translatedText")
        end

        private

        attr_reader :project

        def authorization
          @authorization ||= R3x::Client::GoogleAuth.from_env(
            project: project,
            scope: R3x::Client::GoogleAuth.resolve_scope("translate")
          )
        end

        def authorization_header
          {
            "Authorization" => "Bearer #{access_token}"
          }
        end

        def access_token
          authorization.fetch_access_token! if authorization.access_token.nil? || authorization.expires_within?(30)
          authorization.access_token
        end

        def connection
          @connection ||= Faraday.new do |f|
            f.request :json
            f.response :json
            f.response :raise_error
          end
        end

        def request_body(text, to:, from:, format:)
          {
            q: text,
            target: to,
            source: from,
            format: format
          }.compact
        end
      end
    end
  end
end

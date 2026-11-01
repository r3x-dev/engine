# frozen_string_literal: true

module R3x
  module Client
    class Sourcetap
      DEFAULT_URL_ENV = "SOURCETAP_URL"
      DEFAULT_AUTH_TOKEN_ENV = "SOURCETAP_AUTH_TOKEN"

      def initialize(url_env: DEFAULT_URL_ENV, auth_token_env: DEFAULT_AUTH_TOKEN_ENV)
        url = R3x::Env.secure_fetch(url_env, prefix: "#{DEFAULT_URL_ENV}_")
        token = R3x::Env.secure_fetch(auth_token_env, prefix: "#{DEFAULT_AUTH_TOKEN_ENV}_")
        @mcp = Mcp.new(url:, headers: { "Authorization" => "Bearer #{token}" }, timeout: 65)
      end

      def call_tool(name, arguments: {})
        mcp.call_tool(name, arguments:)
      end

      private

      attr_reader :mcp
    end
  end
end

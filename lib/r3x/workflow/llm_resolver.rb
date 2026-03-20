module R3x
  module Workflow
    class LlmResolver
      API_KEY_PATTERN = /\A[A-Z]+_API_KEY_[A-Z0-9_]+\z/.freeze

      def initialize(api_key_name:)
        @api_key_name = api_key_name
      end

      def analyze_image(...)
        client.analyze_image(...)
      end

      private

      attr_reader :api_key_name

      def client
        @client ||= R3x::Client::Llm.new(
          api_key: resolved_api_key,
          config_attr: config_attr
        )
      end

      def resolved_api_key
        R3x::Env.secure_fetch(api_key_name, prefix: API_KEY_PATTERN)
      end

      def config_attr
        "#{api_key_name.split("_").first.downcase}_api_key"
      end
    end
  end
end

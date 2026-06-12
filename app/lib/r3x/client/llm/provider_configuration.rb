# frozen_string_literal: true

module R3x
  module Client
    class Llm
      class ProviderConfiguration < Data.define(:api_key, :config_api_key_attr)
        API_KEY_SUFFIX = "_API_KEY"

        def self.resolve(api_key_env:)
          raise ArgumentError, "api_key_env is required" if api_key_env.blank?

          R3x::GemLoader.require("ruby_llm")
          ProviderRegistry.register!

          base_name = api_key_env.split(API_KEY_SUFFIX).first
          provider = base_name.downcase.to_sym
          raise ArgumentError, "Unsupported LLM provider for #{api_key_env}: #{provider}" unless RubyLLM::Provider.providers.key?(provider)

          new(
            api_key: R3x::Env.secure_fetch(api_key_env, prefix: "#{base_name}_API_KEY_"),
            config_api_key_attr: "#{provider}_api_key"
          )
        end
      end
    end
  end
end

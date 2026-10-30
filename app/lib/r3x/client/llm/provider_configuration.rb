# frozen_string_literal: true

module R3x
  module Client
    class Llm
      class ProviderConfiguration < Data.define(:api_key, :config_api_key_attr)
        CREDENTIAL_SUFFIX = /_API_(?:KEY|TOKEN)(?=_|\z)/

        def self.resolve(api_key_env:)
          raise ArgumentError, "api_key_env is required" if api_key_env.blank?

          R3x::GemLoader.require("ruby_llm")
          ProviderRegistry.register!

          base_name, suffix = api_key_env.partition(CREDENTIAL_SUFFIX)
          raise ArgumentError, "LLM credential env name must contain _API_KEY or _API_TOKEN" if suffix.empty?

          provider = base_name.downcase.to_sym
          raise ArgumentError, "Unsupported LLM provider for #{api_key_env}: #{provider}" unless RubyLLM::Provider.providers.key?(provider)

          new(api_key: R3x::Env.secure_fetch(api_key_env, prefix: "#{base_name}#{suffix}_"), config_api_key_attr: "#{provider}_api_key")
        end
      end
    end
  end
end

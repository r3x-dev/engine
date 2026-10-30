# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class Llm
      class ProviderConfigurationTest < ActiveSupport::TestCase
        setup do
          @original_env = ENV.to_h
        end

        teardown do
          ENV.replace(@original_env)
        end

        test "requires a present api key env name" do
          [nil, ""].each do |api_key_env|
            error = assert_raises(ArgumentError) do
              ProviderConfiguration.resolve(api_key_env:)
            end
            assert_equal "api_key_env is required", error.message
          end
        end

        test "inferred resolution automatically detects known provider from key name" do
          ENV["GEMINI_API_KEY_MICHAL"] = "michal-key"

          config = ProviderConfiguration.resolve(api_key_env: "GEMINI_API_KEY_MICHAL")

          assert_equal "michal-key", config.api_key
          assert_equal "gemini_api_key", config.config_api_key_attr
        end

        test "accepts key and token env names with and without a suffix" do
          %w[CLOUDFLARE_API_KEY CLOUDFLARE_API_KEY_TEST CLOUDFLARE_API_TOKEN CLOUDFLARE_API_TOKEN_TEST].each_with_index do |name, index|
            ENV[name] = "credential-#{index}"

            config = ProviderConfiguration.resolve(api_key_env: name)

            assert_equal "credential-#{index}", config.api_key
            assert_equal "cloudflare_api_key", config.config_api_key_attr
          end
        end

        test "rejects incomplete credential env names" do
          %w[GEMINI CLOUDFLARE_API_TOKENISH GEMINI_API_KEYTEST].each do |name|
            ENV[name] = "credential"

            assert_raises(ArgumentError) do
              ProviderConfiguration.resolve(api_key_env: name)
            end
          end
        end

        test "inferred resolution raises when provider is unknown" do
          ENV["UNKNOWN_SERVICE_API_KEY"] = "unknown-key"

          error = assert_raises(ArgumentError) do
            ProviderConfiguration.resolve(api_key_env: "UNKNOWN_SERVICE_API_KEY")
          end
          assert_equal "Unsupported LLM provider for UNKNOWN_SERVICE_API_KEY: unknown_service", error.message
        end

        test "for_provider resolution fetches key and applies predefined config" do
          ENV["OPENCODE_GO_API_KEY_TEST"] = "opencode-key"

          config = ProviderConfiguration.resolve(api_key_env: "OPENCODE_GO_API_KEY_TEST")

          assert_equal "opencode-key", config.api_key
          assert_equal "opencode_go_api_key", config.config_api_key_attr
        end
      end
    end
  end
end

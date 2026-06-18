# frozen_string_literal: true

module R3x
  module Client
    class Llm
      module ProviderRegistry
        extend self

        MUTEX = Mutex.new
        CUSTOM_SLUGS = %i[opencode_go].freeze

        def register!
          MUTEX.synchronize { register_opencode_go! }
        end

        private

        def register_opencode_go!
          RubyLLM::Providers.const_set(:OpenCodeGo, opencode_go_provider_class) unless RubyLLM::Providers.const_defined?(:OpenCodeGo, false)
          return if RubyLLM::Provider.providers[:opencode_go] == RubyLLM::Providers::OpenCodeGo

          RubyLLM::Provider.register(:opencode_go, RubyLLM::Providers::OpenCodeGo)
        end

        def opencode_go_provider_class
          Class.new(RubyLLM::Providers::OpenAI) do
            def api_base
              "https://opencode.ai/zen/go/v1"
            end

            def headers
              { "Authorization" => "Bearer #{@config.opencode_go_api_key}" }.compact
            end

            class << self
              def slug
                "opencode_go"
              end

              def assume_models_exist?
                false
              end

              def configuration_options
                %i[opencode_go_api_key]
              end

              def configuration_requirements
                []
              end
            end
          end
        end
      end
    end
  end
end

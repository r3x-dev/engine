# frozen_string_literal: true

module R3x
  module Client
    class Llm
      module Cloudflare
        extend self

        def provider_class
          dialect = protocol_class

          Class.new(RubyLLM::Provider) do
            protocol :system_one, dialect

            def api_base
              account_id = config.cloudflare_account_id
              unless account_id.match?(/\A[0-9a-f]{32}\z/i)
                raise ArgumentError, "Cloudflare Account ID must contain 32 hexadecimal characters"
              end

              "https://api.cloudflare.com/client/v4/accounts/#{account_id}/ai"
            end

            def headers
              { "Authorization" => "Bearer #{config.cloudflare_api_key}" }
            end

            def list_models
              []
            end

            class << self
              def assume_models_exist?
                true
              end

              def configuration_options
                %i[cloudflare_api_key cloudflare_account_id]
              end

              def configuration_requirements
                configuration_options
              end
            end
          end
        end

        private

        def protocol_class
          Class.new(RubyLLM::Protocols::SystemOne) do
            def judgment_url
              "run/@cf/cloudflare/#{model.id}"
            end

            def parse_judgment_response(response, questions:)
              body = response.body
              unless body.is_a?(Hash) && body["success"] == true && body["result"].is_a?(Hash)
                raise RubyLLM::Error.new("Cloudflare returned an invalid judgment response", response:)
              end

              # Cloudflare wraps the System One result in its REST response envelope.
              response.env.body = body.fetch("result")
              super
            end
          end
        end
      end
    end
  end
end

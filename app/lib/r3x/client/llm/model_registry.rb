# frozen_string_literal: true

# Merged model registry for ruby_llm.
#
# The committed `config/llm_models.json` contains only custom-provider models.
# At runtime this module merges it with the registry bundled inside the
# `ruby_llm` gem so built-in providers (Gemini, OpenAI, etc.) stay available.
#
# Both files use the same format as the bundled `ruby_llm/lib/ruby_llm/models.json`.
# Example entry:
#
#   [
#     {
#       "id": "minimax-m3",
#       "provider": "opencode_go",
#       "name": "minimax-m3",
#       "context_window": 4096,
#       "max_output_tokens": 16384,
#       "capabilities": [],
#       "pricing": {},
#       "metadata": { "object": "model", "owned_by": "opencode" },
#       ...
#     }
#   ]
#
module R3x
  module Client
    class Llm
      module ModelRegistry
        extend self

        FILE_PATH = Rails.root.join("config/llm_models.json").freeze
        CONFIGURE_MUTEX = Mutex.new

        def file_path
          FILE_PATH
        end

        def configure!
          CONFIGURE_MUTEX.synchronize do
            return if RubyLLM.config.model_registry_source == self

            RubyLLM.config.model_registry_file = file_path.to_s
            RubyLLM.config.model_registry_source = self
          end
        end

        def read
          custom_models = RubyLLM::Models.read_from_json(file_path.to_s)
          gem_models = RubyLLM::Models.read_from_json(RubyLLM::Configuration.new.model_registry_file)

          validate_model_format!(custom_models, file_path)
          validate_custom_providers!(custom_models)
          validate_model_format!(gem_models, "ruby_llm bundled registry")

          gem_models
            .index_by { |model| model_key(model) }
            .merge(custom_models.index_by { |model| model_key(model) })
            .values
        end

        def refresh!
          R3x::GemLoader.require("ruby_llm")
          ProviderRegistry.register!
          configure!

          custom_models = ProviderRegistry::CUSTOM_SLUGS.filter_map do |slug|
            provider_class = RubyLLM::Provider.providers.fetch(slug)
            next unless provider_class.configured?(RubyLLM.config)

            provider_class.new(RubyLLM.config).list_models
          end.flatten

          validate_model_format!(custom_models, file_path)
          validate_custom_providers!(custom_models)
          RubyLLM::Models.new(custom_models).save_to_json(file_path)
        end

        private

        def model_key(model)
          [ model.provider.to_s, model.id.to_s ]
        end

        def validate_model_format!(models, source)
          unless models.all? { |model| model.is_a?(RubyLLM::Model::Info) }
            raise R3x::ConfigurationError,
              "Invalid model format in #{source}: expected RubyLLM::Model::Info objects"
          end

          models.each do |model|
            id = model.id.to_s
            provider = model.provider.to_s

            if id.empty?
              raise R3x::ConfigurationError,
                "Missing model id in #{source}"
            end

            if provider.empty?
              raise R3x::ConfigurationError,
                "Missing provider for model '#{id}' in #{source}"
            end
          end
        end

        def validate_custom_providers!(models)
          allowed_providers = ProviderRegistry::CUSTOM_SLUGS.map(&:to_s)

          models.each do |model|
            provider = model.provider.to_s
            next if allowed_providers.include?(provider)

            raise R3x::ConfigurationError,
              "Unexpected provider '#{provider}' for model '#{model.id}' in #{file_path}. " \
              "Allowed custom providers: #{allowed_providers.join(", ")}"
          end
        end
      end
    end
  end
end

module R3x
  module Client
    class Llm
      MAX_RETRIES = 3
      RETRY_INTERVAL = 60.0
      RETRY_BACKOFF_FACTOR = 2
      DEFAULT_CHAT_OPTIONS = Hash.new.freeze
      CHAT_OPTIONS_BY_PROVIDER = Hash.new
      CHAT_OPTIONS_BY_PROVIDER_MUTEX = Mutex.new

      class << self
        def chat_options_for(provider)
          CHAT_OPTIONS_BY_PROVIDER_MUTEX.synchronize do
            CHAT_OPTIONS_BY_PROVIDER.fetch(provider) { CHAT_OPTIONS_BY_PROVIDER[provider] = build_chat_options_for(provider) }
          end
        end

        private

        def build_chat_options_for(provider)
          provider_class = RubyLLM::Provider.providers.fetch(provider)

          if provider_class.assume_models_exist?
            { provider: provider, assume_model_exists: true }.freeze
          else
            DEFAULT_CHAT_OPTIONS
          end
        end
      end

      def initialize(
        api_key:,
        config_api_key_attr:,
        max_retries: MAX_RETRIES,
        retry_interval: RETRY_INTERVAL,
        retry_backoff_factor: RETRY_BACKOFF_FACTOR
      )
        R3x::GemLoader.require("ruby_llm")
        ProviderRegistry.register!

        inferred_provider = config_api_key_attr.delete_suffix("_api_key").to_sym
        raise ArgumentError, "Unsupported LLM provider: #{inferred_provider}" unless RubyLLM::Provider.providers.key?(inferred_provider)

        @chat_options = self.class.chat_options_for(inferred_provider)

        @llm_context = RubyLLM.context do |config|
          config.public_send(:"#{config_api_key_attr}=", api_key)
          config.max_retries = max_retries
          config.retry_interval = retry_interval
          config.retry_backoff_factor = retry_backoff_factor
        end
      end

      def analyze_image(image_bytes, prompt:, model:, schema: nil)
        image = StringIO.new(image_bytes).tap { |io| io.set_encoding(Encoding::BINARY) }

        ask_model(model:, prompt:, schema:, attachments: [ image ]).content
      end

      def message(model:, prompt:, schema: nil)
        ask_model(model:, prompt:, schema:)
      end

      def classify(...)
        Classifier.new(method(:message)).classify(...)
      end

      private

      attr_reader :llm_context, :chat_options

      def ask_model(model:, prompt:, schema:, attachments: nil)
        conversation = llm_context.chat(**chat_options.merge(model: model))
        conversation = conversation.with_schema(schema) if schema

        conversation.ask(prompt, with: attachments)
      end
    end
  end
end

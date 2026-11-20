# frozen_string_literal: true

module R3x
  module Client
    class Llm
      include R3x::Concerns::Logger

      CREDENTIAL_SUFFIX = /_API_(?:KEY|TOKEN)(?=_|\z)/
      DEFAULT_CHAT_OPTIONS = {}.freeze
      CHAT_OPTIONS_BY_PROVIDER = {} # rubocop:disable Style/MutableConstant
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
            { provider:, assume_model_exists: true }.freeze
          else
            DEFAULT_CHAT_OPTIONS
          end
        end
      end

      def initialize(api_key_env:, max_retries: nil)
        raise ArgumentError, "api_key_env is required" if api_key_env.blank?

        R3x::GemLoader.require("ruby_llm")
        ProviderRegistry.register!

        provider, api_key = credentials_for(api_key_env)
        RubyLLM.configure { |config| config.logger = logger }
        @chat_options = self.class.chat_options_for(provider)

        @llm_context = RubyLLM.context do |config|
          config.public_send(:"#{provider}_api_key=", api_key)
          config.max_retries = max_retries unless max_retries.nil?
          yield config if block_given?
        end
      end

      def analyze_image(image_bytes, prompt:, model:, schema: nil, thinking_effort: nil)
        image = StringIO.new(image_bytes).tap { it.set_encoding(Encoding::BINARY) }

        ask_model(model:, prompt:, schema:, thinking_effort:, attachments: [image])
      end

      def message(model:, prompt:, schema: nil, thinking_effort: nil)
        ask_model(model:, prompt:, schema:, thinking_effort:)
      end

      def classify(...)
        Classifier.new(method(:message)).classify(...)
      end

      def judge(input, model:, questions:, with: nil)
        with_transient_errors { llm_context.judge(input, model:, questions:, with:, **chat_options) }
      end

      private

      attr_reader :llm_context, :chat_options

      def credentials_for(api_key_env)
        base_name, suffix = api_key_env.partition(CREDENTIAL_SUFFIX)
        raise ArgumentError, "LLM credential env name must contain _API_KEY or _API_TOKEN" if suffix.empty?

        provider = base_name.downcase.to_sym
        raise ArgumentError, "Unsupported LLM provider for #{api_key_env}: #{provider}" unless RubyLLM::Provider.providers.key?(provider)

        [provider, R3x::Env.secure_fetch(api_key_env, prefix: "#{base_name}#{suffix}_")]
      end

      def ask_model(model:, prompt:, schema:, thinking_effort:, attachments: nil)
        with_transient_errors do
          conversation = llm_context.chat(**chat_options.merge(model:))
          conversation = conversation.with_schema(schema) if schema
          conversation = conversation.with_thinking(effort: thinking_effort) unless thinking_effort.nil?

          conversation.ask(prompt, with: attachments)
        end
      end

      def with_transient_errors
        yield
      rescue RubyLLM::RateLimitError,
        RubyLLM::ServerError,
        RubyLLM::ServiceUnavailableError,
        RubyLLM::OverloadedError,
        Faraday::TimeoutError,
        Faraday::ConnectionFailed,
        Faraday::RetriableResponse,
        Timeout::Error,
        Errno::ETIMEDOUT => error
        raise TransientError, error.message
      end
    end
  end
end

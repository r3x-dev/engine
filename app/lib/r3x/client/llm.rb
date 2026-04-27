module R3x
  module Client
    class Llm
      MAX_RETRIES = 3
      RETRY_INTERVAL = 60.0
      RETRY_BACKOFF_FACTOR = 2

      def initialize(api_key:, config_api_key_attr:, max_retries: MAX_RETRIES, retry_interval: RETRY_INTERVAL, retry_backoff_factor: RETRY_BACKOFF_FACTOR)
        R3x::GemLoader.require("ruby_llm")

        @llm_context = RubyLLM.context do |config|
          config.public_send(:"#{config_api_key_attr}=", api_key)
          config.max_retries = max_retries
          config.retry_interval = retry_interval
          config.retry_backoff_factor = retry_backoff_factor
        end
      end

      def analyze_image(image_bytes, prompt:, model:, schema: nil)
        io = StringIO.new(image_bytes)
        io.set_encoding(Encoding::BINARY)

        chat = llm_context.chat(model: model)
        chat = chat.with_schema(schema) if schema
        chat.ask(prompt, with: [ io ]).content
      end

      def message(model:, prompt:, schema: nil)
        conversation = llm_context.chat(model: model)
        conversation = conversation.with_schema(schema) if schema

        conversation.ask(prompt)
      end

      def classify(...)
        Classifier.new(llm_client: llm_context).classify(...)
      end

      private

      attr_reader :llm_context
    end
  end
end

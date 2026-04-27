module R3x
  module Client
    class Llm
      def initialize(api_key:, config_api_key_attr:, max_retries: nil, retry_interval: nil, retry_backoff_factor: nil)
        R3x::GemLoader.require("ruby_llm")

        @llm_context = RubyLLM.context do |config|
          config.public_send(:"#{config_api_key_attr}=", api_key)
          config.retry_interval = retry_interval || 60.0
          config.max_retries = max_retries if max_retries
          config.retry_backoff_factor = retry_backoff_factor if retry_backoff_factor
        end
      end

      def analyze_image(image_bytes, prompt:, model:, schema: nil)
        io = StringIO.new(image_bytes)
        io.set_encoding(Encoding::BINARY)

        chat = @llm_context.chat(model: model, provider: :gemini)
        chat = chat.with_schema(schema) if schema
        chat.ask(prompt, with: [ io ]).content
      end

      def chat(model:)
        @llm_context.chat(model: model, provider: :gemini)
      end

      def message(model:, prompt:, schema: nil)
        conversation = chat(model: model)
        conversation = conversation.with_schema(schema) if schema

        conversation.ask(prompt)
      end
    end
  end
end

module R3x
  module Client
    class Llm
      def initialize(api_key:, config_attr:)
        @llm_context = RubyLLM.context do |config|
          config.public_send(:"#{config_attr}=", api_key)
        end
      end

      def analyze_image(image_bytes, prompt:, model:)
        chat = @llm_context.chat(model: model, provider: :gemini)
        attachment = RubyLLM::Attachment.new(
          StringIO.new(image_bytes).tap { |io| io.set_encoding(Encoding::BINARY) },
          filename: "image.jpg"
        )
        response = chat.ask(prompt, with: [ attachment ])
        response.content
      end

      def chat(model:)
        @llm_context.chat(model: model, provider: :gemini)
      end

      def message(model:, prompt:)
        chat(model: model).ask(prompt)
      end
    end
  end
end

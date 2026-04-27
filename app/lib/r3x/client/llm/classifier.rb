# frozen_string_literal: true

module R3x
  module Client
    class Llm
      class Classifier
        def initialize(llm_client:)
          @llm_client = llm_client
        end

        def classify(text:, model:, categories:, include_reason: false, allow_other: true)
          all_categories = build_categories(categories, allow_other: allow_other)
          schema = build_schema(all_categories.keys, include_reason: include_reason)
          prompt = build_prompt(text, all_categories, include_reason: include_reason)

          chat = llm_client.chat(model: model)
          chat = chat.with_schema(schema)
          chat.ask(prompt).content
        end

        private

        attr_reader :llm_client

        def build_categories(user_categories, allow_other:)
          cats = user_categories.transform_keys(&:to_s)
          cats["other"] = "Does not fit any of the above" if allow_other && !cats.key?("other")
          cats
        end

        def build_schema(category_names, include_reason:)
          R3x::Workflow::LlmSchema.define do
            string :category, enum: category_names
            if include_reason
              string :reason, description: "Brief explanation of why this category was chosen"
            end
          end
        end

        def build_prompt(text, categories, include_reason:)
          categories_list = categories.map { |cat, desc| "- #{cat}: #{desc}" }.join("\n")

          <<~PROMPT
            Classify the following text into exactly one category. Return JSON only

            <categories>
            #{categories_list}
            </categories>

            <text>
            #{text}
            </text>
          PROMPT
        end
      end
    end
  end
end

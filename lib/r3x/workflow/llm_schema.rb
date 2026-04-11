module R3x
  module Workflow
    module LlmSchema
      extend self

      def define(&block)
        R3x::GemLoader.require("ruby_llm/schema")

        Class.new(RubyLLM::Schema, &block)
      end
    end
  end
end

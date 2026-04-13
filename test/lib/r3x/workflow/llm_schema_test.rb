require "test_helper"

module R3x
  module Workflow
    class LlmSchemaTest < ActiveSupport::TestCase
      test "define loads ruby_llm schema lazily and returns a schema class" do
        klass = LlmSchema.define do
          string :status
        end

        assert klass < RubyLLM::Schema
        assert_equal [ :status ], klass.properties.keys
      end
    end
  end
end

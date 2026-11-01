# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class Llm
      class ClassifierTest < ActiveSupport::TestCase
        test "classify returns parsed hash from response" do
          parsed_data = { "category" => "Politics", "reason" => "Government announcement" }
          response = Struct.new(:parsed).new(parsed_data)
          message_method = ->(**) { response }

          classifier = Classifier.new(message_method)
          result = classifier.classify(
            text: "Prime minister gave speech",
            model: "test-model",
            categories: { "Politics" => "Government" },
            include_reason: true,
          )

          assert_equal parsed_data, result
        end

        test "classify passes an explicit effort to message without changing its result" do
          calls = []
          response = Struct.new(:parsed).new({ "category" => "Politics" })
          classifier = Classifier.new(->(**options) { calls << options; response })

          result = classifier.classify(text: "An announcement", model: "test-model", categories: { "Politics" => "Government" }, thinking_effort: :low)

          assert_equal({ "category" => "Politics" }, result)
          assert_equal :low, calls.sole.fetch(:thinking_effort)
        end
      end
    end
  end
end

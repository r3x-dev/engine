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
      end
    end
  end
end

require "test_helper"

module R3x
  module Client
    class LlmTest < ActiveSupport::TestCase
      test "can configure gemini api key dynamically" do
        llm = Llm.new(api_key: "test-key", config_api_key_attr: "gemini_api_key")
        assert_not_nil llm
      end
    end
  end
end

require "test_helper"

module R3x
  module Client
    class LlmTest < ActiveSupport::TestCase
      test "can configure gemini api key dynamically" do
        llm = Llm.new(api_key: "test-key", config_api_key_attr: "gemini_api_key")
        assert_not_nil llm
      end

      test "applies project-level retry_interval default" do
        llm = Llm.new(api_key: "test", config_api_key_attr: "gemini_api_key")
        context = llm.instance_variable_get(:@llm_context)

        assert_equal 60.0, context.config.retry_interval
      end

      test "forwards per-workflow retry overrides" do
        llm = Llm.new(
          api_key: "test",
          config_api_key_attr: "gemini_api_key",
          max_retries: 5,
          retry_interval: 30.0,
          retry_backoff_factor: 4
        )
        context = llm.instance_variable_get(:@llm_context)

        assert_equal 5, context.config.max_retries
        assert_equal 30.0, context.config.retry_interval
        assert_equal 4, context.config.retry_backoff_factor
      end
    end
  end
end

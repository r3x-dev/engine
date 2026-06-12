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

      test "infers provider and assume_model_exists when provider is registered but has no statically registered models" do
        llm = Llm.new(
          api_key: "opencode-key",
          config_api_key_attr: "opencode_go_api_key"
        )
        context = llm.instance_variable_get(:@llm_context)

        mock_chat = mock("chat")
        context.expects(:chat).with(model: "deepseek-chat", provider: :opencode_go, assume_model_exists: true).returns(mock_chat)
        mock_chat.expects(:ask).with("hello").returns(stub(content: "response"))

        assert_equal "response", llm.message(model: "deepseek-chat", prompt: "hello").content

        mock_classify_chat = mock("classify_chat")
        context.expects(:chat).with(model: "deepseek-chat", provider: :opencode_go, assume_model_exists: true).returns(mock_classify_chat)
        mock_classify_chat.expects(:with_schema).with(anything).returns(mock_classify_chat)
        mock_classify_chat.expects(:ask).with(anything).returns(stub(content: '{"category":"other"}'))

        result = llm.classify(text: "some text", model: "deepseek-chat", categories: { "billing" => "billing issues" })
        assert_equal '{"category":"other"}', result
      end

      test "opencode go provider keeps underscore slug for dynamic model context switching" do
        llm = Llm.new(
          api_key: "opencode-key",
          config_api_key_attr: "opencode_go_api_key"
        )
        context = llm.instance_variable_get(:@llm_context)
        chat = context.chat(model: "deepseek-chat", provider: :opencode_go)

        assert_equal "opencode_go", RubyLLM::Providers::OpenCodeGo.slug
        assert_equal "opencode_go", chat.model.provider
        assert_equal "opencode_go", chat.with_context(context).model.provider
      end

      test "does not scan ruby llm model registry during initialization" do
        RubyLLM::Models.instance.expects(:any?).never

        Llm.new(api_key: "opencode-key", config_api_key_attr: "opencode_go_api_key")
      end

      test "provider registry is idempotent" do
        Llm::ProviderRegistry.register!
        Llm::ProviderRegistry.register!

        assert_same RubyLLM::Providers::OpenCodeGo, RubyLLM::Provider.providers.fetch(:opencode_go)
      end

      test "leaves provider unset for registry-backed models" do
        llm = Llm.new(api_key: "gemini-key", config_api_key_attr: "gemini_api_key")
        context = llm.instance_variable_get(:@llm_context)

        mock_chat = mock("chat")
        context.expects(:chat).with(model: "gemini-1.5-flash").returns(mock_chat)
        mock_chat.expects(:ask).with("hello").returns(stub(content: "response"))

        assert_equal "response", llm.message(model: "gemini-1.5-flash", prompt: "hello").content
      end

      test "does not pin chat options to the first provider initialized in a process" do
        gemini = Llm.new(api_key: "gemini-key", config_api_key_attr: "gemini_api_key")
        opencode_go = Llm.new(api_key: "opencode-key", config_api_key_attr: "opencode_go_api_key")

        assert_equal({}, gemini.instance_variable_get(:@chat_options))
        assert_equal({ provider: :opencode_go, assume_model_exists: true }, opencode_go.instance_variable_get(:@chat_options))
      end

      test "memoizes chat options per provider" do
        first = Llm.new(api_key: "first-key", config_api_key_attr: "opencode_go_api_key")
        second = Llm.new(api_key: "second-key", config_api_key_attr: "opencode_go_api_key")

        assert_same first.instance_variable_get(:@chat_options), second.instance_variable_get(:@chat_options)
      end

      test "raises ArgumentError when provider is unregistered" do
        assert_raises(ArgumentError) do
          Llm.new(api_key: "unknown-key", config_api_key_attr: "unknown_service_api_key")
        end
      end
    end
  end
end

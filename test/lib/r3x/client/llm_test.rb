# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class LlmTest < ActiveSupport::TestCase
      class FakeLlmContext
        attr_reader :chat_calls

        def initialize(conversation)
          @chat_calls = []
          @conversation = conversation
        end

        def chat(**options)
          chat_calls << options
          @conversation
        end
      end

      class FakeChat
        Response = Struct.new(:content)

        attr_reader :ask_calls, :schema_calls

        def initialize(*contents)
          @contents = contents
          @ask_calls = []
          @schema_calls = []
        end

        def with_schema(schema)
          schema_calls << schema
          self
        end

        def ask(prompt, with: nil)
          ask_calls << { prompt:, with: }
          Response.new(@contents.shift)
        end
      end

      test "can configure gemini api key dynamically" do
        llm = Llm.new(api_key: "test-key", config_api_key_attr: "gemini_api_key")

        assert_not_nil llm
      end

      test "applies project-level retry_interval default" do
        llm = Llm.new(api_key: "test", config_api_key_attr: "gemini_api_key")
        context = llm.instance_variable_get(:@llm_context)

        assert_in_delta(60.0, context.config.retry_interval)
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
        assert_in_delta(30.0, context.config.retry_interval)
        assert_equal 4, context.config.retry_backoff_factor
      end

      test "infers provider and assume_model_exists when provider is registered but has no statically registered models" do
        chat = FakeChat.new("response", '{"category":"other"}')
        context = FakeLlmContext.new(chat)
        R3x::GemLoader.require("ruby_llm")
        RubyLLM.stubs(:context).returns(context)

        llm = Llm.new(
          api_key: "opencode-key",
          config_api_key_attr: "opencode_go_api_key"
        )

        assert_equal "response", llm.message(model: "deepseek-chat", prompt: "hello").content

        result = llm.classify(text: "some text", model: "deepseek-chat", categories: { "billing" => "billing issues" })

        assert_equal '{"category":"other"}', result
        assert_equal(
          [
            { model: "deepseek-chat", provider: :opencode_go, assume_model_exists: true },
            { model: "deepseek-chat", provider: :opencode_go, assume_model_exists: true }
          ],
          context.chat_calls
        )
        assert_equal 1, chat.schema_calls.size
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

      test "uses provider metadata instead of pinning opencode go to registered models" do
        llm = Llm.new(api_key: "opencode-key", config_api_key_attr: "opencode_go_api_key")

        assert_equal({ provider: :opencode_go, assume_model_exists: true }, llm.instance_variable_get(:@chat_options))
      end

      test "provider registry is idempotent" do
        R3x::GemLoader.require("ruby_llm")

        Llm::ProviderRegistry.register!
        Llm::ProviderRegistry.register!

        assert_same RubyLLM::Providers::OpenCodeGo, RubyLLM::Provider.providers.fetch(:opencode_go)
      end

      test "leaves provider unset for registry-backed models" do
        chat = FakeChat.new("response")
        context = FakeLlmContext.new(chat)
        R3x::GemLoader.require("ruby_llm")
        RubyLLM.stubs(:context).returns(context)

        llm = Llm.new(api_key: "gemini-key", config_api_key_attr: "gemini_api_key")

        assert_equal "response", llm.message(model: "gemini-1.5-flash", prompt: "hello").content
        assert_equal [{ model: "gemini-1.5-flash" }], context.chat_calls
        assert_equal [{ prompt: "hello", with: nil }], chat.ask_calls
      end

      test "analyze_image asks with binary image attachment and returns response content" do
        chat = FakeChat.new("image response")
        context = FakeLlmContext.new(chat)
        R3x::GemLoader.require("ruby_llm")
        RubyLLM.stubs(:context).returns(context)

        llm = Llm.new(api_key: "gemini-key", config_api_key_attr: "gemini_api_key")

        assert_equal "image response", llm.analyze_image("bytes", prompt: "describe", model: "gemini-1.5-flash", schema: :schema)

        image = chat.ask_calls.sole.fetch(:with).sole

        assert_equal [{ model: "gemini-1.5-flash" }], context.chat_calls
        assert_equal [:schema], chat.schema_calls
        assert_equal "describe", chat.ask_calls.sole.fetch(:prompt)
        assert_instance_of StringIO, image
        assert_equal Encoding::BINARY, image.external_encoding
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

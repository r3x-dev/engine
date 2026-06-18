# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class Llm
      class ModelRegistryTest < ActiveSupport::TestCase
        test "merges gem registry with custom registry, custom entries win" do
          R3x::GemLoader.require("ruby_llm")

          Dir.mktmpdir do |dir|
            gem_file = File.join(dir, "gem_models.json")
            custom_file = File.join(dir, "custom_models.json")

            File.write(gem_file, MultiJSON.generate([
              { id: "shared-model", provider: "opencode_go", name: "from-gem" },
              { id: "gem-only", provider: "gemini", name: "Gemini Model" }
            ]))
            File.write(custom_file, MultiJSON.generate([
              { id: "shared-model", provider: "opencode_go", name: "from-custom" }
            ]))

            RubyLLM::Configuration.any_instance.stubs(:model_registry_file).returns(gem_file)
            ModelRegistry.stubs(:file_path).returns(Pathname.new(custom_file))

            models = ModelRegistry.read
            shared = models.find { |m| m.id == "shared-model" && m.provider == "opencode_go" }
            gem_only = models.find { |m| m.id == "gem-only" && m.provider == "gemini" }

            assert_equal "from-custom", shared.name
            assert_equal "Gemini Model", gem_only.name
          end
        end

        test "fetches and persists custom provider models" do
          R3x::GemLoader.require("ruby_llm")
          ProviderRegistry.register!

          custom_model = RubyLLM::Model::Info.new(id: "test-model", provider: "opencode_go")
          provider = mock("provider")
          provider.expects(:list_models).returns([ custom_model ])
          RubyLLM::Providers::OpenCodeGo.stubs(:new).returns(provider)

          Dir.mktmpdir do |dir|
            custom_file = File.join(dir, "custom_models.json")
            ModelRegistry.stubs(:file_path).returns(Pathname.new(custom_file))

            ModelRegistry.refresh!

            persisted = RubyLLM::Models.read_from_json(custom_file)

            assert_equal 1, persisted.size
            assert_equal "test-model", persisted.first.id
            assert_equal "opencode_go", persisted.first.provider
          end
        end

        test "configures ruby_llm to use merged registry" do
          R3x::GemLoader.require("ruby_llm")

          ModelRegistry.configure!

          assert_equal ModelRegistry.file_path.to_s, RubyLLM.config.model_registry_file
          assert_same ModelRegistry, RubyLLM.config.model_registry_source
        end

        test "configure! is idempotent" do
          R3x::GemLoader.require("ruby_llm")

          3.times { ModelRegistry.configure! }

          assert_equal ModelRegistry.file_path.to_s, RubyLLM.config.model_registry_file
          assert_same ModelRegistry, RubyLLM.config.model_registry_source
        end

        test "raises when custom registry contains unexpected provider" do
          R3x::GemLoader.require("ruby_llm")

          Dir.mktmpdir do |dir|
            gem_file = File.join(dir, "gem_models.json")
            custom_file = File.join(dir, "custom_models.json")

            File.write(gem_file, MultiJSON.generate([]))
            File.write(custom_file, MultiJSON.generate([
              { id: "unknown-model", provider: "unknown_provider" }
            ]))

            RubyLLM::Configuration.any_instance.stubs(:model_registry_file).returns(gem_file)
            ModelRegistry.stubs(:file_path).returns(Pathname.new(custom_file))

            error = assert_raises(R3x::ConfigurationError) { ModelRegistry.read }

            assert_includes error.message, "unknown_provider"
            assert_includes error.message, "opencode_go"
          end
        end
      end
    end
  end
end

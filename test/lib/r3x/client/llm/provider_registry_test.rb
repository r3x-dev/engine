# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class Llm
      class ProviderRegistryTest < ActiveSupport::TestCase
        setup do
          R3x::GemLoader.require("ruby_llm")
          ProviderRegistry.register!
        end

        test "opencode_go provider participates in model registry refresh" do
          provider_class = RubyLLM::Provider.providers.fetch(:opencode_go)

          assert_operator provider_class, :<, RubyLLM::Providers::OpenAI
          refute_predicate provider_class, :assume_models_exist?
          assert_empty provider_class.configuration_requirements
        end

        test "opencode_go provider lists models via public endpoint" do
          stub_request(:get, "https://opencode.ai/zen/go/v1/models")
            .to_return(
              status: 200,
              body: MultiJSON.generate(
                object: "list",
                data: [
                  { id: "kimi-k2.7-code", object: "model", created: 1_700_000_000, owned_by: "opencode" }
                ]
              ),
              headers: { "Content-Type" => "application/json" }
            )

          provider = RubyLLM::Providers::OpenCodeGo.new(RubyLLM.config)
          models = provider.list_models

          assert_equal 1, models.size
          assert_equal "kimi-k2.7-code", models.first.id
          assert_equal "opencode_go", models.first.provider
        end
      end
    end
  end
end

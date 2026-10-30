# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class Llm
      class CloudflareTest < ActiveSupport::TestCase
        setup do
          @original_env = ENV.to_h
          ENV["CLOUDFLARE_API_KEY_TEST"] = "test-token"
          ENV["CLOUDFLARE_ACCOUNT_ID_TEST"] = "a" * 32
        end

        teardown do
          ENV.replace(@original_env)
        end

        test "judges through the workflow client with native typed answers and usage" do
          request = stub_request(:post, endpoint)
            .with(headers: { "Authorization" => "Bearer test-token" }) do |http_request|
              payload = MultiJSON.parse(http_request.body)
              payload.fetch("model") == "clef-flash" && payload.fetch("state") == "Public works announced" &&
                payload.dig("questions", "relevant", "type") == "noul" &&
                payload.dig("questions", "topic", "criteria", "society") == "Local civic news" &&
                payload.dig("questions", "importance", "criteria") == %w[Minor Major]
            end.to_return(status: 200, headers: json_headers, body: MultiJSON.generate(success_body))

          judgment = client.judge("Public works announced", model: "clef-flash", questions:)

          assert_equal "society", judgment.topic.choice
          assert_in_delta 0.9, judgment.topic.probabilities.fetch("society")
          assert_in_delta 0.8, judgment.relevant.probability
          assert_in_delta 0.75, judgment.importance.score
          assert_equal 202, judgment.tokens.input
          assert_equal 0, judgment.tokens.output
          assert_requested request, times: 1
        end

        test "keeps credentials and accounts isolated between clients" do
          first = client
          ENV["CLOUDFLARE_API_KEY_OTHER"] = "other-token"
          ENV["CLOUDFLARE_ACCOUNT_ID_OTHER"] = "b" * 32
          second = R3x::Workflow::Context::Client.llm(
            api_key_env: "CLOUDFLARE_API_KEY_OTHER", max_retries: 0,
          ) do |config|
            config.cloudflare_account_id = R3x::Env.fetch!("CLOUDFLARE_ACCOUNT_ID_OTHER")
          end
          [
            [first, endpoint, "test-token"],
            [second, endpoint("b" * 32), "other-token"],
          ].each do |llm, url, token|
            request = stub_request(:post, url).with(headers: { "Authorization" => "Bearer #{token}" })
              .to_return(status: 200, headers: json_headers, body: MultiJSON.generate(success_body))

            assert_equal "society", llm.judge("Public works announced", model: "clef-flash", questions:).topic.choice
            assert_requested request, times: 1
          end
        end

        test "uses unsuffixed key env and explicit provider configuration" do
          ENV["CLOUDFLARE_API_KEY"] = "base-token"
          ENV["CLOUDFLARE_ACCOUNT_ID"] = "a" * 32
          request = stub_request(:post, endpoint).with(headers: { "Authorization" => "Bearer base-token" })
            .to_return(status: 200, headers: json_headers, body: MultiJSON.generate(success_body))
          llm = R3x::Workflow::Context::Client.llm(api_key_env: "CLOUDFLARE_API_KEY", max_retries: 0) do |config|
            config.cloudflare_account_id = R3x::Env.fetch!("CLOUDFLARE_ACCOUNT_ID")
          end

          assert_equal "society", llm.judge("Public works announced", model: "clef-flash", questions:).topic.choice
          assert_requested request, times: 1
        end

        test "uses an api token env name through the workflow client" do
          ENV["CLOUDFLARE_API_TOKEN_TEST"] = "named-token"
          request = stub_request(:post, endpoint).with(headers: { "Authorization" => "Bearer named-token" })
            .to_return(status: 200, headers: json_headers, body: MultiJSON.generate(success_body))
          llm = R3x::Workflow::Context::Client.llm(api_key_env: "CLOUDFLARE_API_TOKEN_TEST", max_retries: 0) do |config|
            config.cloudflare_account_id = R3x::Env.fetch!("CLOUDFLARE_ACCOUNT_ID_TEST")
          end

          assert_equal "society", llm.judge("Public works announced", model: "clef-flash", questions:).topic.choice
          assert_requested request, times: 1
        end

        test "translates rate limits to the workflow transient error without retrying" do
          request = stub_request(:post, endpoint)
            .to_return(status: 429, headers: json_headers, body: '{"success":false,"errors":[{"code":10000,"message":"Rate limited"}]}')
          llm = client

          assert_raises(TransientError) do
            llm.judge("Public works announced", model: "clef-flash", questions:)
          end
          assert_requested request, times: 1
        end

        test "keeps authentication errors fatal" do
          stub_request(:post, endpoint).to_return(status: 401, headers: json_headers, body: '{"success":false}')
          llm = client

          assert_raises(RubyLLM::UnauthorizedError) do
            llm.judge("Public works announced", model: "clef-flash", questions:)
          end
        end

        test "rejects unsuccessful or malformed successful responses" do
          [{ success: false }, { success: true, result: {} }].each do |body|
            stub_request(:post, endpoint).to_return(status: 200, headers: json_headers, body: MultiJSON.generate(body))
            llm = client

            assert_raises(RubyLLM::Error) do
              llm.judge("Public works announced", model: "clef-flash", questions:)
            end
          end
        end

        test "requires provider configuration and a valid account id" do
          llm = R3x::Workflow::Context::Client.llm(api_key_env: "CLOUDFLARE_API_KEY_TEST", max_retries: 0)
          assert_raises(RubyLLM::ConfigurationError) do
            llm.judge("Public works announced", model: "clef-flash", questions:)
          end

          ENV["CLOUDFLARE_ACCOUNT_ID_TEST"] = "../another-account"
          llm = client
          assert_raises(ArgumentError) do
            llm.judge("Public works announced", model: "clef-flash", questions:)
          end
        end

        private

        def client
          R3x::Workflow::Context::Client.llm(api_key_env: "CLOUDFLARE_API_KEY_TEST", max_retries: 0) do |config|
            config.cloudflare_account_id = R3x::Env.fetch!("CLOUDFLARE_ACCOUNT_ID_TEST")
          end
        end

        def endpoint(account_id = "a" * 32)
          "https://api.cloudflare.com/client/v4/accounts/#{account_id}/ai/run/@cf/cloudflare/clef-flash"
        end

        def json_headers
          { "Content-Type" => "application/json" }
        end

        def questions
          {
            relevant: { type: :probability, instructions: "Is it relevant?" },
            topic: { type: :choice, instructions: "Choose the main topic", options: { "society" => "Local civic news", "other" => "Other" } },
            importance: { type: :score, instructions: "Rate importance", levels: %w[Minor Major] },
          }
        end

        def success_body
          {
            success: true,
            result: {
              model: "clef-flash",
              answers: {
                relevant: { type: "noul", noul: 0.8 },
                topic: { type: "choice", choice: "society", probabilities: { society: 0.9, other: 0.1 }, confidence: 0.8 },
                importance: { type: "score", score: 0.75, legend: { "0" => "Minor", "1" => "Major" }, probabilities: { "0" => 0.25, "1" => 0.75 }, confidence: 0.6 },
              },
              usage: { input_tokens: 202, output_tokens: 0 },
            },
          }
        end
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class DiscordTest < ActiveSupport::TestCase
      test "deliver sends content and waits for a message using webhook url via env" do
        original_query_notation = WebMock::Config.instance.query_values_notation
        WebMock::Config.instance.query_values_notation = :flat_array
        webhook_url = "https://discord.test/webhook?wait=false&thread_id=thread-123&flags=4&flags=8&wait=0&label=a%2Bb+value"
        delivered = nil
        delivered_query = nil
        response_message = { "id" => "message-123", "content" => "Hello Discord",
                             "channel_id" => "channel-123", "author" => { "id" => "bot-123" } }

        request = stub_request(:post, %r{\Ahttps://discord\.test/webhook(?:\?.*)?\z})
          .with do |req|
            delivered = MultiJSON.parse(req.body)
            delivered_query = URI.decode_www_form(URI.parse(req.uri.to_s).query)
            true
          end
          .to_return(status: 200, body: response_message.to_json,
            headers: { "Content-Type" => "application/json" })

        with_env("R3X_DISCORD_DRY_RUN" => "false", "DISCORD_WEBHOOK_URL_TEST" => webhook_url) do
          result = Discord.new(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST").deliver(content: "Hello Discord")

          assert_equal({ "content" => "Hello Discord" }, delivered)
          assert_equal [%w[wait true]], delivered_query.select { |key, _| key == "wait" }
          assert_equal [["flags", "4"], ["flags", "8"], ["label", "a+b value"], ["thread_id", "thread-123"]],
            delivered_query.reject { |key, _| key == "wait" }
          assert_instance_of Delivery, result
          assert_predicate result, :delivered?
          assert_equal response_message, result.message
          assert_requested request
        end
      ensure
        WebMock::Config.instance.query_values_notation = original_query_notation
      end

      test "deliver sends content to default webhook url env" do
        webhook_url = "https://discord.test/default-webhook"
        delivered = nil

        stub_request(:post, "#{webhook_url}?wait=true")
          .with do |req|
            delivered = MultiJSON.parse(req.body)
          end
          .to_return(status: 200, body: { id: "message-123" }.to_json,
            headers: { "Content-Type" => "application/json" })

        with_env("R3X_DISCORD_DRY_RUN" => "false", "DISCORD_WEBHOOK_URL" => webhook_url) do
          result = Discord.new.deliver(content: "Hello Discord")

          assert_equal({ "content" => "Hello Discord" }, delivered)
          assert_instance_of Delivery, result
          assert_predicate result, :delivered?
          assert_equal "message-123", result.message.fetch("id")
        end
      end

      test "rejects webhook env names outside discord prefix" do
        with_env("WEBHOOK_URL" => "https://discord.test/webhook") do
          error = assert_raises(ArgumentError) do
            Discord.new(webhook_url_env: "WEBHOOK_URL")
          end

          assert_equal "Key 'WEBHOOK_URL' must be 'DISCORD_WEBHOOK_URL' or start with 'DISCORD_WEBHOOK_URL_'", error.message
        end
      end

      test "deliver raises on non-2xx response" do
        webhook_url = "https://discord.test/webhook"

        stub_request(:post, "#{webhook_url}?wait=true")
          .to_return(status: 404)

        with_env("R3X_DISCORD_DRY_RUN" => "false", "DISCORD_WEBHOOK_URL_TEST" => webhook_url) do
          assert_raises(HTTPX::HTTPError) do
            Discord.new(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST").deliver(content: "Hello")
          end
        end
      end

      test "deliver returns dry_run when dry run is active" do
        webhook_url = "https://discord.test/webhook"
        request = stub_request(:post, "#{webhook_url}?wait=true")

        with_env("R3X_DISCORD_DRY_RUN" => "true", "DISCORD_WEBHOOK_URL_TEST" => webhook_url) do
          result = nil
          output = capture_logged_output do
            result = Discord.new(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST").deliver(content: "private message")
          end

          assert_instance_of Delivery, result
          assert_predicate result, :dry_run?
          assert_nil result.message
          assert_not_requested request
          assert_includes output, "DRY-RUN"
          assert_includes output, "action=deliver content_length=15"
          assert_includes output, 'content_preview=\"private message\"'
        end
      end

      test "deliver accepts explicit webhook_url" do
        webhook_url = "https://discord.test/webhook"
        delivered = nil

        stub_request(:post, "#{webhook_url}?wait=true")
          .with do |req|
            delivered = MultiJSON.parse(req.body)
          end
          .to_return(status: 200, body: { id: "message-123" }.to_json,
            headers: { "Content-Type" => "application/json" })

        with_env("R3X_DISCORD_DRY_RUN" => "false") do
          result = Discord.new(webhook_url:).deliver(content: "Hello Discord")

          assert_equal({ "content" => "Hello Discord" }, delivered)
          assert_instance_of Delivery, result
          assert_predicate result, :delivered?
          assert_equal "message-123", result.message.fetch("id")
        end
      end

      test "deliver does not treat an empty 204 response as success" do
        webhook_url = "https://discord.test/webhook"

        stub_request(:post, "#{webhook_url}?wait=true").to_return(status: 204)

        with_env("R3X_DISCORD_DRY_RUN" => "false", "DISCORD_WEBHOOK_URL_TEST" => webhook_url) do
          assert_raises(HTTPX::Error) do
            Discord.new(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST").deliver(content: "Hello")
          end
        end
      end

      test "deliver propagates malformed JSON responses" do
        webhook_url = "https://discord.test/webhook"

        stub_request(:post, "#{webhook_url}?wait=true").to_return(status: 200, body: "{not-json",
          headers: { "Content-Type" => "application/json" })

        with_env("R3X_DISCORD_DRY_RUN" => "false", "DISCORD_WEBHOOK_URL_TEST" => webhook_url) do
          assert_raises(JSON::ParserError) do
            Discord.new(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST").deliver(content: "Hello")
          end
        end
      end

      [[], nil, { "other" => "value" }, { "id" => "" }, { "id" => " \t" }, { "id" => 123 }].each do |response_body|
        test "deliver rejects invalid response receipt #{response_body.inspect}" do
          webhook_url = "https://discord.test/webhook"

          stub_request(:post, "#{webhook_url}?wait=true").to_return(status: 200, body: MultiJSON.generate(response_body),
            headers: { "Content-Type" => "application/json" })

          with_env("R3X_DISCORD_DRY_RUN" => "false", "DISCORD_WEBHOOK_URL_TEST" => webhook_url) do
            assert_raises(ArgumentError) do
              Discord.new(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST").deliver(content: "Hello")
            end
          end
        end
      end

      test "raises when neither webhook_url nor webhook_url_env is provided" do
        assert_raises(ArgumentError) do
          Discord.new
        end
      end

      test "raises when webhook_url_env is blank" do
        assert_raises(ArgumentError) do
          Discord.new(webhook_url_env: "")
        end
      end

      private

      def with_env(hash)
        originals = hash.each_with_object({}) { |(k, _), memo| memo[k] = ENV[k] }
        hash.each { |k, v| ENV[k] = v }
        yield
      ensure
        originals.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end
    end
  end
end

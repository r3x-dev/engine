require "test_helper"

module R3x
  module Client
    class DiscordTest < ActiveSupport::TestCase
      test "deliver sends content to webhook url via env" do
        webhook_url = "https://discord.test/webhook"
        delivered = nil

        stub_request(:post, webhook_url)
          .with do |req|
            delivered = MultiJson.load(req.body)
          end
          .to_return(status: 204)

        with_env("R3X_DISCORD_DRY_RUN" => "false", "DISCORD_WEBHOOK_URL_TEST" => webhook_url) do
          result = Discord.new(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST").deliver(content: "Hello Discord")

          assert_equal({ "content" => "Hello Discord" }, delivered)
          assert_equal({ "mode" => "real", "content" => "Hello Discord" }, result)
        end
      end

      test "deliver raises on non-2xx response" do
        webhook_url = "https://discord.test/webhook"

        stub_request(:post, webhook_url)
          .to_return(status: 404)

        with_env("R3X_DISCORD_DRY_RUN" => "false", "DISCORD_WEBHOOK_URL_TEST" => webhook_url) do
          assert_raises(HTTPX::HTTPError) do
            Discord.new(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST").deliver(content: "Hello")
          end
        end
      end

      test "deliver returns dry_run when dry run is active" do
        webhook_url = "https://discord.test/webhook"

        with_env("R3X_DISCORD_DRY_RUN" => "true", "DISCORD_WEBHOOK_URL_TEST" => webhook_url) do
          result = Discord.new(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST").deliver(content: "Hello")

          assert_equal({ "mode" => "dry_run" }, result)
        end
      end

      test "deliver accepts explicit webhook_url" do
        webhook_url = "https://discord.test/webhook"
        delivered = nil

        stub_request(:post, webhook_url)
          .with do |req|
            delivered = MultiJson.load(req.body)
          end
          .to_return(status: 204)

        with_env("R3X_DISCORD_DRY_RUN" => "false") do
          result = Discord.new(webhook_url: webhook_url).deliver(content: "Hello Discord")

          assert_equal({ "content" => "Hello Discord" }, delivered)
          assert_equal({ "mode" => "real", "content" => "Hello Discord" }, result)
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

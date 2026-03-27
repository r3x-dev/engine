require "test_helper"

module R3x
  module Outputs
    class DiscordTest < ActiveSupport::TestCase
      test "deliver returns dry-run payload without calling webhook client" do
        discord = Discord.new(dry_run: true)

        with_stubbed_discord_webhook_class do
          assert_equal(
            {
              "content" => "Hello Discord",
              "delivery_mode" => "dry-run"
            },
            discord.deliver(content: "Hello Discord")
          )
        end
      end

      test "deliver calls webhook client in real mode" do
        original_webhook_url = ENV["R3X_DISCORD_WEBHOOK_URL"]
        delivered_content = nil
        webhook_instance = Object.new
        webhook_instance.define_singleton_method(:deliver) do |content:|
          delivered_content = content
        end

        ENV["R3X_DISCORD_WEBHOOK_URL"] = "https://discord.test/webhook"

        with_stubbed_discord_webhook_class(webhook_instance) do
          result = Discord.new(dry_run: false).deliver(content: "Hello Discord")

          assert_equal "Hello Discord", delivered_content
          assert_equal(
            {
              "content" => "Hello Discord",
              "delivery_mode" => "real"
            },
            result
          )
        end
      ensure
        ENV["R3X_DISCORD_WEBHOOK_URL"] = original_webhook_url
      end

      private

      def with_stubbed_discord_webhook_class(instance = nil)
        client_module = R3x::Client
        original_defined = client_module.const_defined?(:DiscordWebhook, false)
        original_class = client_module.const_get(:DiscordWebhook) if original_defined

        fake_class = Class.new do
          define_method(:initialize) do |webhook_url:|
            @webhook_url = webhook_url
          end

          define_method(:deliver) do |content:|
            instance&.deliver(content: content)
          end
        end

        client_module.send(:remove_const, :DiscordWebhook) if original_defined
        client_module.const_set(:DiscordWebhook, fake_class)

        yield
      ensure
        client_module.send(:remove_const, :DiscordWebhook) if client_module.const_defined?(:DiscordWebhook, false)
        client_module.const_set(:DiscordWebhook, original_class) if original_defined
      end
    end
  end
end

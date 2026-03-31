require "test_helper"

module R3x
  module Client
    class DiscordTest < ActiveSupport::TestCase
      test "deliver sends content to webhook url" do
        webhook_url = "https://discord.test/webhook"
        delivered = nil

        stub_request(:post, webhook_url)
          .with do |req|
            delivered = MultiJson.load(req.body)
          end
          .to_return(status: 204)

        result = Discord.new(webhook_url: webhook_url).deliver(content: "Hello Discord")

        assert_equal({ "content" => "Hello Discord" }, delivered)
        assert_equal({ "mode" => "real", "content" => "Hello Discord" }, result)
      end

      test "deliver raises on non-2xx response" do
        webhook_url = "https://discord.test/webhook"

        stub_request(:post, webhook_url)
          .to_return(status: 404)

        assert_raises(Faraday::ResourceNotFound) do
          Discord.new(webhook_url: webhook_url).deliver(content: "Hello")
        end
      end
    end
  end
end

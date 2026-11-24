# frozen_string_literal: true

require "test_helper"

module R3x
  module Triggers
    class DiscordMessageTest < ActiveSupport::TestCase
      test "groups only original image attachments in order by message or attachment" do
        message = discord_message
        base_payload = {
          "channel_id" => "100",
          "message_id" => "200",
          "content"    => "Three posters",
        }
        images = %w[400 402 403].map { |id| { "id" => id } }

        assert_equal [base_payload.merge("attachments" => images)], payloads(:message, message)
        assert_equal images.map { |image| base_payload.merge("attachments" => [image]) }, payloads(:attachment, message)
      end

      test "ignores images from other channels, unauthorized senders, bots, and webhooks" do
        message = discord_message

        assert_empty payloads(:message, message.merge("channel_id" => "101"))
        assert_empty payloads(:message, message.merge("author" => { "id" => "301" }))
        assert_empty payloads(:message, message.merge("author" => { "id" => "300", "bot" => true }))
        assert_empty payloads(:message, message.merge("webhook_id" => "500"))
      end

      test "ignores images in replies and forwards when the message has no image attachments" do
        message = discord_message
        video = message.fetch("attachments").fetch(1)
        message["attachments"] = [video]

        assert_empty payloads(:message, message)
      end

      test "requires a stable key, channel ID, image filter and supported grouping" do
        workflow = Class.new(R3x::Workflow::Base)

        error = assert_raises(ConfigurationError) do
          workflow.trigger(:discord_message, channel_id: "chat", attachments: :all, run_per: :user)
        end

        assert_includes error.message, "Key can't be blank"
        assert_includes error.message, "Channel is invalid"
        assert_includes error.message, "Attachments is not included in the list"
        assert_includes error.message, "Run per is not included in the list"
      end

      private

      def payloads(run_per, message)
        workflow = Class.new(R3x::Workflow::Base)
        trigger = workflow.trigger(:discord_message, key: :posters, channel_id: 100, attachments: :images, run_per:)
        trigger.payloads(message, allowed_author_ids: ["300"])
      end

      def discord_message
        forwarded = { "attachments" => [{ "id" => "404", "content_type" => "image/png" }] }
        {
          "id"                 => "200",
          "channel_id"         => "100",
          "author"             => { "id" => "300" },
          "content"            => "Three posters",
          "attachments"        => [
            { "id" => "400", "content_type" => "image/png" },
            { "id" => "401", "content_type" => "video/mp4", "height" => 1024, "width" => 512 },
            { "id" => "402", "content_type" => "image/jpeg" },
            { "id" => "403", "content_type" => "image/webp" },
          ],
          "referenced_message" => forwarded,
          "message_snapshots"  => [{ "message" => forwarded }],
        }
      end
    end
  end
end

# frozen_string_literal: true

module R3x
  module Triggers
    class DiscordMessage < Base
      attr_reader :channel_id

      validates :key, presence: true
      validates :channel_id, format: { with: /\A[1-9][0-9]*\z/ }
      validates :attachments, inclusion: { in: [:images] }
      validates :run_per, inclusion: { in: %i[message attachment] }

      def initialize(key: nil, channel_id: nil, attachments: nil, run_per: nil)
        @channel_id = channel_id.to_s
        super(:discord_message, key:, channel_id: @channel_id, attachments:, run_per:)
      end

      def payloads(message, allowed_author_ids:)
        return [] unless message.fetch("channel_id") == channel_id
        return [] if message["webhook_id"]

        author = message.fetch("author")
        return [] if author["bot"] || !allowed_author_ids.include?(author.fetch("id"))

        images = message.fetch("attachments").filter_map do |attachment|
          next unless attachment["content_type"]&.start_with?("image/")

          { "id" => attachment.fetch("id") }
        end
        return [] if images.empty?

        payload = {
          "channel_id" => channel_id,
          "message_id" => message.fetch("id"),
          "content"    => message.fetch("content"),
        }
        case run_per
        when :message
          [payload.merge("attachments" => images)]
        when :attachment
          images.map { |image| payload.merge("attachments" => [image]) }
        else
          raise ArgumentError, "Unsupported Discord run_per: #{run_per.inspect}"
        end
      end

      private

      def attachments
        options.fetch(:attachments)
      end

      def run_per
        options.fetch(:run_per)
      end
    end
  end
end

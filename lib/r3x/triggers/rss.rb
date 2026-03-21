require "rss"

module R3x
  module Triggers
    class Rss < Base
      include Concerns::CronSchedulable
      include Concerns::ChangeDetecting

      validates :url, presence: true
      validates_with Validators::Url, url_field: :url

      def initialize(url: nil, cron: nil, **options)
        normalized_url = url.is_a?(String) ? url.strip : url
        normalized_cron = cron.is_a?(String) ? cron.strip : cron
        super(:rss, url: normalized_url, cron: normalized_cron, **options)
      end

      def url
        options[:url]
      end

      def cron
        options[:cron]
      end

      def unique_key
        "rss:#{Digest::SHA256.hexdigest(url)[0..15]}"
      end

      def detect_changes(workflow_key:, state:)
        response = Faraday.get(url)
        raise Faraday::Error, "HTTP #{response.status}" unless response.success?

        feed = RSS::Parser.parse(response.body, false)

        current_links = extract_links(feed)
        seen_links = (state[:seen_links] || []).map(&:to_s)
        new_links = current_links - seen_links

        if new_links.empty?
          { changed: false, state: { seen_links: current_links }, payload: nil }
        else
          new_items = feed.items.select { |item|
            link = extract_link(item)
            new_links.include?(link)
          }

          {
            changed: true,
            state: { seen_links: current_links },
            payload: {
              feed_title: extract_feed_title(feed),
              feed_url: url,
              new_items: new_items.map { |item|
                {
                  title: extract_title(item),
                  link: extract_link(item),
                  published_at: extract_published(item),
                  description: extract_description(item)
                }
              }
            }
          }
        end
      end

      private

      def extract_links(feed)
        feed.items.map { |item| extract_link(item) }.compact
      end

      def extract_link(item)
        if item.respond_to?(:link) && item.link.is_a?(RSS::Atom::Feed::Link)
          item.link.href
        elsif item.respond_to?(:link) && item.link.is_a?(String)
          item.link.presence
        elsif item.respond_to?(:guid) && item.guid
          item.guid.content
        end
      end

      def extract_feed_title(feed)
        title = if feed.respond_to?(:channel) && feed.channel
          feed.channel.title
        else
          feed.title
        end
        extract_text(title)
      end

      def extract_title(item)
        extract_text(item.title)
      end

      def extract_text(value)
        return nil if value.nil?
        value.respond_to?(:content) ? value.content : value.to_s
      end

      def extract_published(item)
        if item.respond_to?(:pubDate) && item.pubDate
          item.pubDate.to_s
        elsif item.respond_to?(:published) && item.published
          item.published.to_s
        elsif item.respond_to?(:updated) && item.updated
          item.updated.to_s
        end
      end

      def extract_description(item)
        if item.respond_to?(:description) && item.description
          item.description
        elsif item.respond_to?(:content) && item.content
          item.content
        elsif item.respond_to?(:summary) && item.summary
          item.summary
        end
      end
    end
  end
end

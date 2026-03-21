require "test_helper"

module R3x
  class RssTriggerTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    SAMPLE_RSS_FEED = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <link>https://example.com</link>
          <description>A test RSS feed</description>
          <item>
            <title>First Post</title>
            <link>https://example.com/first</link>
            <description>Description of first post</description>
            <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
          </item>
          <item>
            <title>Second Post</title>
            <link>https://example.com/second</link>
            <description>Description of second post</description>
            <pubDate>Tue, 02 Jan 2024 12:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML

    SAMPLE_RSS_FEED_UPDATED = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <link>https://example.com</link>
          <description>A test RSS feed</description>
          <item>
            <title>Third Post</title>
            <link>https://example.com/third</link>
            <description>Description of third post</description>
            <pubDate>Wed, 03 Jan 2024 12:00:00 GMT</pubDate>
          </item>
          <item>
            <title>First Post</title>
            <link>https://example.com/first</link>
            <description>Description of first post</description>
            <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML

    SAMPLE_ATOM_FEED = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test Atom Feed</title>
        <link href="https://example.com/atom" rel="alternate"/>
        <entry>
          <title>Atom Entry</title>
          <link href="https://example.com/atom-entry" rel="alternate"/>
          <id>https://example.com/atom-entry</id>
          <published>2024-01-01T12:00:00Z</published>
        </entry>
      </feed>
    XML

    # Validation tests

    test "validates presence of url" do
      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end
          trigger :rss, cron: "every 15 minutes"
        end
      end

      assert_includes error.message, "Url can't be blank"
    end

    test "validates presence of cron" do
      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end
          trigger :rss, url: "https://example.com/feed.xml"
        end
      end

      assert_includes error.message, "Cron can't be blank"
    end

    test "validates url format" do
      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end
          trigger :rss, url: "not a url", cron: "every 15 minutes"
        end
      end

      assert_includes error.message, "is not a valid HTTP/HTTPS URL"
    end

    test "validates cron format" do
      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end
          trigger :rss, url: "https://example.com/feed.xml", cron: "bad cron"
        end
      end

      assert_includes error.message, "Cron is not a valid cron expression"
    end

    test "accepts valid rss trigger configuration" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Test"
        end
        trigger :rss, url: "https://example.com/feed.xml", cron: "every 15 minutes"
      end

      trigger = klass.schedulable_triggers.first
      assert trigger
      assert_equal :rss, trigger.type
      assert_equal "https://example.com/feed.xml", trigger.url
      assert trigger.cron_schedulable?
      assert trigger.change_detecting?
    end

    # unique_key tests

    test "unique_key is based on url" do
      trigger = R3x::Triggers::Rss.new(url: "https://example.com/feed.xml", cron: "every 15 minutes")
      assert_match(/\Arss:[a-f0-9]{16}\z/, trigger.unique_key)
    end

    test "unique_key does not change when cron changes" do
      trigger_one = R3x::Triggers::Rss.new(url: "https://example.com/feed.xml", cron: "every 15 minutes")
      trigger_two = R3x::Triggers::Rss.new(url: "https://example.com/feed.xml", cron: "every hour")

      assert_equal trigger_one.unique_key, trigger_two.unique_key
    end

    test "different urls produce different unique_keys" do
      trigger_one = R3x::Triggers::Rss.new(url: "https://example.com/feed1.xml", cron: "every 15 minutes")
      trigger_two = R3x::Triggers::Rss.new(url: "https://example.com/feed2.xml", cron: "every 15 minutes")

      refute_equal trigger_one.unique_key, trigger_two.unique_key
    end

    # detect_changes tests

    test "first check with empty state detects all items as new" do
      stub_request(:get, "https://example.com/feed.xml").to_return(status: 200, body: SAMPLE_RSS_FEED)

      trigger = R3x::Triggers::Rss.new(url: "https://example.com/feed.xml", cron: "every 15 minutes")
      result = trigger.detect_changes(workflow_key: "test", state: {})

      assert result[:changed]
      assert_equal "Test Feed", result[:payload][:feed_title]
      assert_equal "https://example.com/feed.xml", result[:payload][:feed_url]
      assert_equal 2, result[:payload][:new_items].size

      first_item = result[:payload][:new_items].first
      assert_equal "First Post", first_item[:title]
      assert_equal "https://example.com/first", first_item[:link]
      assert_equal "Description of first post", first_item[:description]
      assert first_item[:published_at]

      assert_equal [ "https://example.com/first", "https://example.com/second" ], result[:state][:seen_links]
    end

    test "second check with same feed reports no changes" do
      stub_request(:get, "https://example.com/feed.xml").to_return(status: 200, body: SAMPLE_RSS_FEED)

      trigger = R3x::Triggers::Rss.new(url: "https://example.com/feed.xml", cron: "every 15 minutes")

      state = { seen_links: [ "https://example.com/first", "https://example.com/second" ] }
      result = trigger.detect_changes(workflow_key: "test", state: state)

      refute result[:changed]
      assert_nil result[:payload]
    end

    test "detects new items added to feed" do
      stub_request(:get, "https://example.com/feed.xml").to_return(status: 200, body: SAMPLE_RSS_FEED_UPDATED)

      trigger = R3x::Triggers::Rss.new(url: "https://example.com/feed.xml", cron: "every 15 minutes")

      state = { seen_links: [ "https://example.com/first", "https://example.com/second" ] }
      result = trigger.detect_changes(workflow_key: "test", state: state)

      assert result[:changed]
      assert_equal 1, result[:payload][:new_items].size
      assert_equal "Third Post", result[:payload][:new_items].first[:title]
      assert_equal "https://example.com/third", result[:payload][:new_items].first[:link]

      assert_equal [ "https://example.com/third", "https://example.com/first" ], result[:state][:seen_links]
    end

    test "handles Atom feeds" do
      stub_request(:get, "https://example.com/atom.xml").to_return(status: 200, body: SAMPLE_ATOM_FEED)

      trigger = R3x::Triggers::Rss.new(url: "https://example.com/atom.xml", cron: "every 15 minutes")
      result = trigger.detect_changes(workflow_key: "test", state: {})

      assert result[:changed]
      assert_equal "Test Atom Feed", result[:payload][:feed_title]
      assert_equal 1, result[:payload][:new_items].size
      assert_equal "Atom Entry", result[:payload][:new_items].first[:title]
    end

    test "raises on HTTP error" do
      stub_request(:get, "https://example.com/feed.xml").to_return(status: 500, body: "Internal Server Error")

      trigger = R3x::Triggers::Rss.new(url: "https://example.com/feed.xml", cron: "every 15 minutes")

      assert_raises(Faraday::Error) do
        trigger.detect_changes(workflow_key: "test", state: {})
      end
    end

    test "handles empty feed gracefully" do
      empty_feed = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Empty Feed</title>
          </channel>
        </rss>
      XML

      stub_request(:get, "https://example.com/empty.xml").to_return(status: 200, body: empty_feed)

      trigger = R3x::Triggers::Rss.new(url: "https://example.com/empty.xml", cron: "every 15 minutes")
      result = trigger.detect_changes(workflow_key: "test", state: {})

      refute result[:changed]
      assert_nil result[:payload]
    end

    # Integration with workflow DSL

    test "rss trigger integrates with workflow dsl" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::RssWatcher"
        end
        trigger :rss, url: "https://example.com/feed.xml", cron: "every 15 minutes"
      end

      trigger = klass.schedulable_triggers.first
      assert_equal :rss, trigger.type
      assert trigger.cron_schedulable?
      assert trigger.change_detecting?
    end

    test "rss trigger appears in supported types" do
      assert_includes R3x::Triggers.supported_types, :rss
    end
  end
end

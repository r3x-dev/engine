require "test_helper"

module R3x
  module Services
    class RssParserTest < ActiveSupport::TestCase
      test "parses rss feed into normalized item hashes" do
        body = File.read(Rails.root.join("test/fixtures/files/rss_test.xml"))

        items = R3x::Services::RssParser.new.parse(body, source_url: "https://example.com/rss")

        assert_equal 2, items.size
        assert_equal "https://example.com/article-1", items.first.fetch("url")
        assert_equal "First test article description", items.first.fetch("body")
        assert_equal "rss", items.first.fetch("source_type")
        assert_equal "https://example.com/rss", items.first.fetch("source_url")
      end
    end
  end
end

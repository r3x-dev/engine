require "test_helper"

module R3x
  module Validators
    class UrlTest < ActiveSupport::TestCase
      test "accepts valid HTTP URL" do
        assert_nothing_raised do
          Url.validate!("http://example.com/rss")
        end
      end

      test "accepts valid HTTPS URL" do
        assert_nothing_raised do
          Url.validate!("https://example.com/rss")
        end
      end

      test "accepts URL with path and query" do
        assert_nothing_raised do
          Url.validate!("https://example.com/feed.xml?format=rss")
        end
      end

      test "rejects invalid URL" do
        assert_raises(ArgumentError) do
          Url.validate!("not a url")
        end
      end

      test "rejects FTP URL" do
        assert_raises(ArgumentError) do
          Url.validate!("ftp://example.com/file")
        end
      end

      test "rejects empty URL" do
        assert_nothing_raised do
          Url.validate!("")
        end
      end

      test "rejects nil URL" do
        assert_nothing_raised do
          Url.validate!(nil)
        end
      end

      test "uses custom field name in error message" do
        error = assert_raises(ArgumentError) do
          Url.validate!("invalid", field_name: "feed_url")
        end
        assert_match(/feed_url:/, error.message)
      end
    end
  end
end

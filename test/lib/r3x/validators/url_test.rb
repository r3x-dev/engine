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

      # ActiveModel::Validator form tests

      class DummyModel
        include ActiveModel::Validations

        attr_reader :url

        validates_with Url, url_field: :url

        def initialize(url:)
          @url = url
        end
      end

      class DummyModelAllowBlank
        include ActiveModel::Validations

        attr_reader :url

        validates_with Url, url_field: :url, allow_blank: true

        def initialize(url:)
          @url = url
        end
      end

      test "ActiveModel form accepts valid URL" do
        model = DummyModel.new(url: "https://example.com/feed")
        assert model.valid?
      end

      test "ActiveModel form rejects invalid URL" do
        model = DummyModel.new(url: "not a url")
        assert_not model.valid?
        assert_includes model.errors[:url], "url: 'not a url' is not a valid HTTP/HTTPS URL"
      end

      test "ActiveModel form rejects blank when not allowed" do
        model = DummyModel.new(url: nil)
        assert_not model.valid?
      end

      test "ActiveModel form allows blank when configured" do
        model = DummyModelAllowBlank.new(url: nil)
        assert model.valid?
      end
    end
  end
end

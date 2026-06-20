# frozen_string_literal: true

require "test_helper"

module R3x
  module Dashboard
    class ErrorParserTest < ActiveSupport::TestCase
      test "summarizes hash errors from message or error keys" do
        assert_equal "boom", ErrorParser.new({ "message" => "boom" }).summary
        assert_equal "bad", ErrorParser.new({ error: "bad" }).summary
      end

      test "summarizes plain text errors from the first line" do
        parser = ErrorParser.new("boom\nfull details")

        assert_equal "boom", parser.summary
        assert_equal "boom\nfull details", parser.body
        assert_predicate parser, :details_visible?
      end

      test "summarizes inline JSON message values" do
        parser = ErrorParser.new('{"message":"the server responded with status 403"}')

        assert_equal "the server responded with status 403", parser.summary
      end

      test "parses JSON error text into structured error data" do
        error = ErrorParser.new(
          MultiJSON.generate(
            exception_class: "HTTPX::HTTPError",
            message: "the server responded with status 403",
            backtrace: ["line one", "line two"],
          ),
        ).structured

        assert_equal "HTTPX::HTTPError", error[:exception_class]
        assert_equal "the server responded with status 403", error[:message]
        assert_equal ["line one", "line two"], error[:backtrace]
      end

      test "parses ruby hash dumps into structured error data" do
        error = ErrorParser.new(
          '{"exception_class" => "HTTPX::HTTPError", "message" => "the server responded with status 403", "backtrace" => ["line one", "line two"]}',
        ).structured

        assert_equal "HTTPX::HTTPError", error[:exception_class]
        assert_equal "the server responded with status 403", error[:message]
        assert_equal ["line one", "line two"], error[:backtrace]
      end

      test "falls back for blank errors" do
        parser = ErrorParser.new(nil)

        assert_equal "Unknown error", parser.summary
        assert_equal "No error details recorded.", parser.body
        assert_nil parser.structured
      end
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module R3x
  module Dashboard
    class ErrorDetailsTest < ActiveSupport::TestCase
      test "summarizes hash errors from message or error keys" do
        assert_equal "boom", ErrorDetails.new({ "message" => "boom" }).summary
        assert_equal "bad", ErrorDetails.new({ error: "bad" }).summary
      end

      test "summarizes plain text errors from the first line" do
        details = ErrorDetails.new("boom\nfull details")

        assert_equal "boom", details.summary
        assert_equal "boom\nfull details", details.body
        assert_predicate details, :details_visible?
      end

      test "summarizes inline JSON message values" do
        details = ErrorDetails.new('{"message":"the server responded with status 403"}')

        assert_equal "the server responded with status 403", details.summary
      end

      test "parses JSON error text into structured error data" do
        error = ErrorDetails.new(
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
        error = ErrorDetails.new(
          '{"exception_class" => "HTTPX::HTTPError", "message" => "the server responded with status 403", "backtrace" => ["line one", "line two"]}',
        ).structured

        assert_equal "HTTPX::HTTPError", error[:exception_class]
        assert_equal "the server responded with status 403", error[:message]
        assert_equal ["line one", "line two"], error[:backtrace]
      end

      test "falls back for blank errors" do
        details = ErrorDetails.new(nil)

        assert_equal "Unknown error", details.summary
        assert_equal "No error details recorded.", details.body
        assert_nil details.structured
      end
    end
  end
end

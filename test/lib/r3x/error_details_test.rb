# frozen_string_literal: true

require "test_helper"

module R3x
  class ErrorDetailsTest < ActiveSupport::TestCase
    test "normalizes exceptions" do
      exception = ArgumentError.new("boom")
      exception.set_backtrace(["app/lib/a.rb:1", "app/lib/b.rb:2"])

      details = ErrorDetails.new(exception)

      assert_equal "ArgumentError", details.error_class
      assert_equal "boom", details.message
      assert_equal ["app/lib/a.rb:1", "app/lib/b.rb:2"], details.backtrace
      assert_equal "boom", details.summary
      assert_equal "ArgumentError: boom\napp/lib/a.rb:1\napp/lib/b.rb:2", details.body
      assert_predicate details, :details_visible?
      assert_equal(
        { error_class: "ArgumentError", message: "boom", backtrace: ["app/lib/a.rb:1", "app/lib/b.rb:2"] },
        details.structured,
      )
    end

    test "normalizes canonical hash keys" do
      details = ErrorDetails.new(
        "error_class" => "NameError",
        "message"     => "uninitialized constant",
        "backtrace"   => ["app/lib/a.rb:1"],
      )

      assert_equal "NameError", details.error_class
      assert_equal "uninitialized constant", details.message
      assert_equal ["app/lib/a.rb:1"], details.backtrace
      assert_equal(
        { error_class: "NameError", message: "uninitialized constant", backtrace: ["app/lib/a.rb:1"] },
        details.structured,
      )
    end

    test "normalizes legacy hash keys" do
      details = ErrorDetails.new(
        exception_class: "HTTPX::HTTPError",
        error_message: "forbidden",
        trace: ["line one"],
      )

      assert_equal "HTTPX::HTTPError", details.error_class
      assert_equal "forbidden", details.message
      assert_equal ["line one"], details.backtrace
    end

    test "normalizes error and stack hash keys" do
      details = ErrorDetails.new(error: "bad", stack: ["line one"])

      assert_nil details.error_class
      assert_equal "bad", details.message
      assert_equal ["line one"], details.backtrace
    end

    test "normalizes json strings" do
      details = ErrorDetails.new(
        MultiJSON.generate(
          exception_class: "HTTPX::HTTPError",
          error_message: "forbidden",
          trace: ["line one", "line two"],
        ),
      )

      assert_equal(
        { error_class: "HTTPX::HTTPError", message: "forbidden", backtrace: ["line one", "line two"] },
        details.structured,
      )
    end

    test "normalizes ruby hash dumps" do
      details = ErrorDetails.new(
        '{"exception_class" => "HTTPX::HTTPError", "error" => "forbidden", "stack" => ["line one", "line two"]}',
      )

      assert_equal(
        { error_class: "HTTPX::HTTPError", message: "forbidden", backtrace: ["line one", "line two"] },
        details.structured,
      )
    end

    test "preserves plain text fallback behavior" do
      details = ErrorDetails.new("boom\nfull details")

      assert_equal "boom", details.summary
      assert_equal "boom\nfull details", details.body
      assert_predicate details, :details_visible?
      assert_nil details.structured
    end

    test "preserves blank fallback behavior" do
      details = ErrorDetails.new(nil)

      assert_equal "Unknown error", details.summary
      assert_equal "No error details recorded.", details.body
      assert_nil details.structured
    end
  end
end

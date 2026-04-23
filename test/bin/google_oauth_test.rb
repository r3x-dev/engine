# frozen_string_literal: true

require "test_helper"
require "thor"
require "highline"
load Rails.root.join("bin/google-oauth").to_s

class GoogleOAuthCLITest < ActiveSupport::TestCase
  setup do
    @cli = GoogleOAuthCLI.new
  end

  test "interactive_scope_selection returns all aliases when 'all' is chosen" do
    all_aliases = R3x::Client::GoogleAuth.scope_aliases.keys

    mock_highline = Object.new

    mock_highline.define_singleton_method(:choose) do |&block|
      menu = Object.new
      menu.define_singleton_method(:prompt=) { |*| }
      menu.define_singleton_method(:choice) { |*_args| }
      block.call(menu)
      :all
    end

    mock_highline.define_singleton_method(:ask) do |*_args, **_kwargs, &block|
      q = Object.new
      q.define_singleton_method(:default=) { |*| }
      block.call(q) if block
      "y"
    end

    original_new = HighLine.method(:new)
    HighLine.define_singleton_method(:new) { mock_highline }

    _, _ = capture_io do
      result = @cli.send(:interactive_scope_selection)
      assert_equal all_aliases.sort, result.split(",").sort
    end
  ensure
    HighLine.define_singleton_method(:new, original_new)
  end

  test "authorize fails fast before scope selection when GOOGLE_CLIENT_ID is missing" do
    @cli.define_singleton_method(:options) { { "project" => "MISSING" } }

    scope_selection_called = false
    @cli.define_singleton_method(:interactive_scope_selection) do
      scope_selection_called = true
      ""
    end

    assert_raises(SystemExit) do
      capture_io { @cli.authorize }
    end

    assert_equal false, scope_selection_called, "interactive_scope_selection should not be called when credentials are missing"
  end

  test "authorize fails fast before scope selection when GOOGLE_CLIENT_SECRET is missing" do
    @cli.define_singleton_method(:options) { { "project" => "MISSING" } }

    original_fetch = R3x::Env.method(:fetch)
    call_count = 0
    R3x::Env.define_singleton_method(:fetch) do |key|
      call_count += 1
      return "fake-client-id" if key == "GOOGLE_CLIENT_ID_MISSING"
      original_fetch.call(key)
    end

    scope_selection_called = false
    @cli.define_singleton_method(:interactive_scope_selection) do
      scope_selection_called = true
      ""
    end

    assert_raises(SystemExit) do
      capture_io { @cli.authorize }
    end

    assert_equal false, scope_selection_called, "interactive_scope_selection should not be called when client_secret is missing"
  ensure
    R3x::Env.define_singleton_method(:fetch, original_fetch)
  end

  test "extract_code_from_url extracts code from redirect URL" do
    code = @cli.send(:extract_code_from_url, "http://localhost/?code=4/0AX4XfWh&scope=email")

    assert_equal "4/0AX4XfWh", code
  end

  test "extract_code_from_url aborts when code is missing" do
    assert_raises(SystemExit) do
      capture_io { @cli.send(:extract_code_from_url, "http://localhost/?error=access_denied") }
    end
  end

  test "extract_code_from_url aborts on invalid URL" do
    assert_raises(SystemExit) do
      capture_io { @cli.send(:extract_code_from_url, "not-a-url") }
    end
  end
end

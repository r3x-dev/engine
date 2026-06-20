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

    mock_highline = Class.new do
      def choose
        menu = Struct.new(:prompt) do
          def choice(*)
          end
        end.new
        yield menu
        :all
      end

      def ask(*, **)
        question = Struct.new(:default).new
        yield question if block_given?
        "y"
      end
    end.new

    HighLine.stubs(:new).returns(mock_highline)

    _, _ = capture_io do
      result = @cli.send(:interactive_scope_selection)

      assert_equal all_aliases.sort, result.split(",").sort
    end
  end

  test "authorize fails fast before scope selection when GOOGLE_CLIENT_ID is missing" do
    @cli.stubs(:options).returns({ "project" => "MISSING" })

    @cli.expects(:interactive_scope_selection).never

    assert_raises(SystemExit) do
      capture_io { @cli.authorize }
    end
  end

  test "authorize fails fast before scope selection when GOOGLE_CLIENT_SECRET is missing" do
    @cli.stubs(:options).returns({ "project" => "MISSING" })

    R3x::Env.stubs(:fetch!).with("GOOGLE_CLIENT_ID_MISSING").returns("fake-client-id")
    R3x::Env.stubs(:fetch!).with("GOOGLE_CLIENT_SECRET_MISSING").raises(ArgumentError, "Missing env key: GOOGLE_CLIENT_SECRET_MISSING")

    @cli.expects(:interactive_scope_selection).never

    assert_raises(SystemExit) do
      capture_io { @cli.authorize }
    end
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

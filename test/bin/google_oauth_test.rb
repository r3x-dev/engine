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

    R3x::Env.stubs(:fetch).with("GOOGLE_CLIENT_ID_MISSING").returns(nil)
    @cli.expects(:interactive_scope_selection).never

    assert_raises(SystemExit) do
      capture_io { @cli.authorize }
    end
  end

  test "authorize fails fast before scope selection when GOOGLE_CLIENT_SECRET is missing" do
    @cli.stubs(:options).returns({ "project" => "MISSING" })

    R3x::Env.stubs(:fetch).with("GOOGLE_CLIENT_ID_MISSING").returns("fake-client-id")
    R3x::Env.stubs(:fetch).with("GOOGLE_CLIENT_SECRET_MISSING").returns(nil)

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

  test "current_scopes prints granted scopes and aliases" do
    fake_client = Struct.new(:access_token) do
      def fetch_access_token!
        true
      end
    end.new("access-token")

    @cli.stubs(:options).returns({ "project" => "TESTPROJ" })
    R3x::Env.stubs(:fetch).with("GOOGLE_CLIENT_ID_TESTPROJ").returns("client-id")
    R3x::Env.stubs(:fetch).with("GOOGLE_CLIENT_SECRET_TESTPROJ").returns("client-secret")
    R3x::Env.stubs(:fetch).with("GOOGLE_REFRESH_TOKEN_TESTPROJ").returns("refresh-token")
    Signet::OAuth2::Client.stubs(:new).returns(fake_client)

    stub_request(:get, "https://oauth2.googleapis.com/tokeninfo")
      .with(query: { "access_token" => "access-token" })
      .to_return(
        status: 200,
        body: MultiJSON.generate("scope" => "https://www.googleapis.com/auth/cloud-translation https://www.googleapis.com/auth/gmail.send"),
        headers: { "Content-Type" => "application/json" },
      )

    output, _ = capture_io { @cli.current_scopes }

    assert_includes output, "https://www.googleapis.com/auth/cloud-translation"
    assert_includes output, "https://www.googleapis.com/auth/gmail.send"
    assert_includes output, "translate"
    assert_includes output, "gmail.send"
  end

  test "add_scopes authorizes current scopes plus requested additions" do
    @cli.stubs(:options).returns({ "project" => "TESTPROJ", "scopes" => "gmail.send" })
    @cli.stubs(:current_scope_values).with("TESTPROJ").returns(["https://www.googleapis.com/auth/cloud-translation"])
    @cli.expects(:authorize_project).with(project: "TESTPROJ", scope_aliases: "translate,gmail.send")

    capture_io { @cli.add_scopes }
  end

  test "remove_scopes authorizes current scopes without requested removals" do
    @cli.stubs(:options).returns({ "project" => "TESTPROJ", "scopes" => "gmail.readonly" })
    @cli.stubs(:current_scope_values).with("TESTPROJ").returns([
      "https://www.googleapis.com/auth/gmail.readonly",
      "https://www.googleapis.com/auth/gmail.send",
    ])
    @cli.expects(:authorize_project).with(project: "TESTPROJ", scope_aliases: "gmail.send")

    capture_io { @cli.remove_scopes }
  end

  test "scope_names_for preserves unknown scopes" do
    aliases = @cli.send(:scope_names_for, [
      "https://www.googleapis.com/auth/gmail.send",
      "https://www.googleapis.com/auth/custom.scope",
    ])

    assert_equal ["gmail.send", "https://www.googleapis.com/auth/custom.scope"], aliases
  end
end

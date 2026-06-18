require "test_helper"

module R3x
  module Client
    class GoogleAuthTest < ActiveSupport::TestCase
      test "resolve_scope loads gmail constants lazily" do
        scope = GoogleAuth.resolve_scope("gmail.send")

        assert_equal ::Google::Apis::GmailV1::AUTH_GMAIL_SEND, scope
      end

      test "from_env resolves scope aliases and loads credentials from env" do
        stub_client = mock("signet_client")
        captured = {}

        stub_client.stubs(:fetch_access_token!).returns(true)
        Signet::OAuth2::Client.stubs(:new).with do |**kwargs|
          captured = kwargs
          true
        end.returns(stub_client)

        with_env(
          "GOOGLE_CLIENT_ID_TESTPROJ"     => "client-id",
          "GOOGLE_CLIENT_SECRET_TESTPROJ" => "client-secret",
          "GOOGLE_REFRESH_TOKEN_TESTPROJ" => "refresh-token"
        ) do
          GoogleAuth.from_env(project: "TESTPROJ", scope: "gmail.send")
        end

        assert_equal "client-id", captured.fetch(:client_id)
        assert_equal "client-secret", captured.fetch(:client_secret)
        assert_equal "refresh-token", captured.fetch(:refresh_token)
        assert_equal [ ::Google::Apis::GmailV1::AUTH_GMAIL_SEND ], captured.fetch(:scope)
      end

      test "from_env loads googleauth on first use" do
        GoogleAuth.expects(:require_googleauth!).once
        stub_client = Object.new
        stub_client.stubs(:fetch_access_token!)
        Signet::OAuth2::Client.stubs(:new).returns(stub_client)

        with_env(
          "GOOGLE_CLIENT_ID_TESTPROJ"     => "client-id",
          "GOOGLE_CLIENT_SECRET_TESTPROJ" => "client-secret",
          "GOOGLE_REFRESH_TOKEN_TESTPROJ" => "refresh-token"
        ) do
          GoogleAuth.from_env(project: "TESTPROJ", scope: "gmail.send")
        end
      end

      test "from_json loads googleauth on first use" do
        stub_client = mock("signet_client")

        GoogleAuth.expects(:require_googleauth!).once
        stub_client.stubs(:fetch_access_token!).returns(true)
        Signet::OAuth2::Client.stubs(:new).returns(stub_client)

        GoogleAuth.from_json(
          {
            "client_id"     => "client-id",
            "client_secret" => "client-secret",
            "refresh_token" => "refresh-token"
          },
          scope: "gmail.send"
        )
      end

      test "from_json resolves scope aliases before fetching token" do
        R3x::GemLoader.require("googleauth")

        stub_client = mock("signet_client")
        captured_scope = nil

        stub_client.stubs(:fetch_access_token!).returns(true)

        Signet::OAuth2::Client.stubs(:new).with do |**kwargs|
          captured_scope = kwargs.fetch(:scope)
          true
        end.returns(stub_client)

        GoogleAuth.from_json(
          {
            "client_id"     => "client-id",
            "client_secret" => "client-secret",
            "refresh_token" => "refresh-token"
          },
          scope: "gmail.send"
        )

        assert_equal [ ::Google::Apis::GmailV1::AUTH_GMAIL_SEND ], captured_scope
      end

      test "resolve_scope resolves translate alias directly" do
        scope = GoogleAuth.resolve_scope("translate")

        assert_equal "https://www.googleapis.com/auth/cloud-translation", scope
      end

      test "resolve_scope returns raw value for unknown aliases" do
        assert_equal "https://example.test/scope", GoogleAuth.resolve_scope("https://example.test/scope")
      end

      private

      def with_env(hash)
        old_values = {}
        hash.each do |key, value|
          old_values[key] = ENV[key]
          ENV[key] = value
        end
        yield
      ensure
        old_values.each do |key, value|
          ENV[key] = value
        end
      end
    end
  end
end

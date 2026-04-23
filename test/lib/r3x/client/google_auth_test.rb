require "test_helper"

module R3x
  module Client
    class GoogleAuthTest < ActiveSupport::TestCase
      test "resolve_scope loads gmail constants lazily" do
        scope = GoogleAuth.resolve_scope("gmail.send")

        assert_equal ::Google::Apis::GmailV1::AUTH_GMAIL_SEND, scope
      end

      test "from_env resolves scope aliases and loads credentials from env" do
        stub_client = Object.new
        captured = {}

        stub_client.define_singleton_method(:fetch_access_token!) { true }

        original_new = Signet::OAuth2::Client.method(:new)
        Signet::OAuth2::Client.singleton_class.define_method(:new) do |**kwargs|
          captured = kwargs
          stub_client
        end

        with_env(
          "GOOGLE_CLIENT_ID_TESTPROJ" => "client-id",
          "GOOGLE_CLIENT_SECRET_TESTPROJ" => "client-secret",
          "GOOGLE_REFRESH_TOKEN_TESTPROJ" => "refresh-token"
        ) do
          GoogleAuth.from_env(project: "TESTPROJ", scope: "gmail.send")
        end

        assert_equal "client-id", captured.fetch(:client_id)
        assert_equal "client-secret", captured.fetch(:client_secret)
        assert_equal "refresh-token", captured.fetch(:refresh_token)
        assert_equal [ ::Google::Apis::GmailV1::AUTH_GMAIL_SEND ], captured.fetch(:scope)
      ensure
        Signet::OAuth2::Client.singleton_class.define_method(:new, original_new)
      end

      test "from_json loads googleauth on first use" do
        required_features = []
        original_require = R3x::GemLoader.method(:require)
        stub_client = Object.new
        original_new = nil

        stub_client.define_singleton_method(:fetch_access_token!) { true }

        R3x::GemLoader.singleton_class.define_method(:require) do |feature|
          required_features << feature
          result = original_require.call(feature)

          if feature == "googleauth" && original_new.nil?
            original_new = Signet::OAuth2::Client.method(:new)
            Signet::OAuth2::Client.singleton_class.define_method(:new) do |**_kwargs|
              stub_client
            end
          end

          result
        end

        GoogleAuth.from_json(
          {
            "client_id" => "client-id",
            "client_secret" => "client-secret",
            "refresh_token" => "refresh-token"
          },
          scope: "gmail.send"
        )

        assert_includes required_features, "googleauth"
      ensure
        R3x::GemLoader.singleton_class.define_method(:require, original_require)
        Signet::OAuth2::Client.singleton_class.define_method(:new, original_new) if original_new
      end

      test "from_json resolves scope aliases before fetching token" do
        R3x::GemLoader.require("googleauth")

        stub_client = Object.new
        captured_scope = nil

        stub_client.define_singleton_method(:fetch_access_token!) { true }

        Signet::OAuth2::Client.stubs(:new).with { |**kwargs|
          captured_scope = kwargs.fetch(:scope)
          true
        }.returns(stub_client)

        GoogleAuth.from_json(
          {
            "client_id" => "client-id",
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

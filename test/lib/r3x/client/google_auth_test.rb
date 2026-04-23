require "test_helper"

module R3x
  module Client
    class GoogleAuthTest < ActiveSupport::TestCase
      test "resolve_scope loads gmail constants lazily" do
        scope = GoogleAuth.resolve_scope("gmail.send")

        assert_equal ::Google::Apis::GmailV1::AUTH_GMAIL_SEND, scope
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

        original_new = Signet::OAuth2::Client.method(:new)
        Signet::OAuth2::Client.singleton_class.define_method(:new) do |**kwargs|
          captured_scope = kwargs.fetch(:scope)
          stub_client
        end

        GoogleAuth.from_json(
          {
            "client_id" => "client-id",
            "client_secret" => "client-secret",
            "refresh_token" => "refresh-token"
          },
          scope: "gmail.send"
        )

        assert_equal [ ::Google::Apis::GmailV1::AUTH_GMAIL_SEND ], captured_scope
      ensure
        Signet::OAuth2::Client.singleton_class.define_method(:new, original_new)
      end

      test "resolve_scope returns raw value for unknown aliases" do
        assert_equal "https://example.test/scope", GoogleAuth.resolve_scope("https://example.test/scope")
      end
    end
  end
end

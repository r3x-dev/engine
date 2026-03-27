require "test_helper"

module R3x
  module Outputs
    class GmailTest < ActiveSupport::TestCase
      test "deliver returns dry-run payload without calling gmail api in dry-run mode" do
        gmail = R3x::Outputs::Gmail.new(credentials_env: "GOOGLE_CREDENTIALS_MISSING", dry_run: true)

        with_dry_run_google_client_guard do
          assert_equal(
            { "mode" => "dry-run" },
            gmail.deliver(to: "recipient@example.com", subject: "Hello", body: "Body")
          )
        end
      end

      test "defaults to dry-run in test environment" do
        gmail = R3x::Outputs::Gmail.new(credentials_env: "GOOGLE_CREDENTIALS_MISSING")

        with_dry_run_google_client_guard do
          assert_equal(
            { "mode" => "dry-run" },
            gmail.deliver(to: "recipient@example.com", subject: "Hello", body: "Body")
          )
        end
      end

      test "delegates to google client in real mode" do
        delivered = nil
        captured_credentials_env = nil
        client = Object.new
        client.define_singleton_method(:deliver) do |to:, subject:, body:|
          delivered = [ to, subject, body ]
          { "mode" => "real", "message_id" => "message-123" }
        end

        ENV["GOOGLE_CREDENTIALS_TEST_APP"] = MultiJson.dump(
          client_id: "client-id",
          client_secret: "client-secret",
          refresh_token: "refresh-token"
        )

        singleton_class = R3x::Client::Google::Gmail.singleton_class
        original_method = R3x::Client::Google::Gmail.method(:new)

        singleton_class.define_method(:new) do |credentials_env:|
          captured_credentials_env = credentials_env
          client
        end

        result = R3x::Outputs::Gmail.new(credentials_env: "GOOGLE_CREDENTIALS_TEST_APP", dry_run: false).deliver(
          to: "recipient@example.com",
          subject: "Hello",
          body: "Body"
        )

        assert_equal [ "recipient@example.com", "Hello", "Body" ], delivered
        assert_equal({ "mode" => "real", "message_id" => "message-123" }, result)
        assert_equal "GOOGLE_CREDENTIALS_TEST_APP", captured_credentials_env
      ensure
        singleton_class.define_method(:new, original_method)
        ENV.delete("GOOGLE_CREDENTIALS_TEST_APP")
      end

      private

      def with_dry_run_google_client_guard
        singleton_class = R3x::Client::Google::Gmail.singleton_class
        original_method = R3x::Client::Google::Gmail.method(:new)

        singleton_class.define_method(:new) do |_credentials_env:|
          raise "expected dry-run to skip Google client"
        end

        yield
      ensure
        singleton_class.define_method(:new, original_method)
      end
    end
  end
end

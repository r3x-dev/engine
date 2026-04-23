require "test_helper"

module R3x
  module Client
    module Google
      class GmailTest < ActiveSupport::TestCase
        test "deliver sends encoded message" do
          required_features = []
          original_require = R3x::GemLoader.method(:require)
          authorization = Object.new
          service = Object.new
          service.define_singleton_method(:authorization=) { |value| @authorization = value }
          service.define_singleton_method(:authorization) { @authorization }
          service.define_singleton_method(:send_user_message) do |_user_id, message|
            @delivered_message = message
            Struct.new(:id).new("message-123")
          end
          service.define_singleton_method(:delivered_message) { @delivered_message }

          R3x::GemLoader.singleton_class.define_method(:require) do |feature|
            required_features << feature
            original_require.call(feature)
          end

          with_env("R3X_GMAIL_DRY_RUN" => "false") do
            R3x::Client::GoogleAuth.stubs(:from_env).with { |**kwargs|
              kwargs[:project] == "TEST_APP" && kwargs[:scope].is_a?(String)
            }.returns(authorization)

            with_stubbed_gmail_service(service) do
              result = Gmail.new(project: "TEST_APP").deliver(
                to: "recipient@example.com",
                subject: "Hello",
                body: "Body"
              )

              assert_equal authorization, service.authorization
              assert_equal({ "mode" => "real", "message_id" => "message-123" }, result)
              assert_includes required_features, "mail"
              assert_includes service.delivered_message.raw, "To: recipient@example.com"
              assert_includes service.delivered_message.raw, "Subject: Hello"
              assert_includes service.delivered_message.raw, "Body"
            end
          end
        ensure
          R3x::GemLoader.singleton_class.define_method(:require, original_require)
        end

        test "deliver returns dry_run mode without sending when dry run is active" do
          with_env("R3X_GMAIL_DRY_RUN" => "true") do
            result = Gmail.new(project: "TEST_APP").deliver(
              to: "recipient@example.com",
              subject: "Hello",
              body: "Body"
            )

            assert_equal({ "mode" => "dry_run" }, result)
          end
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

        def with_stubbed_gmail_service(result)
          R3x::Client::GoogleAuth.require_gmail!

          gmail_service_class = ::Google::Apis::GmailV1::GmailService
          original_new = gmail_service_class.method(:new)

          gmail_service_class.define_singleton_method(:new) do
            result
          end

          yield
        ensure
          gmail_service_class.define_singleton_method(:new, original_new) if gmail_service_class && original_new
        end
      end
    end
  end
end

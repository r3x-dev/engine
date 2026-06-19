# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    module Google
      class GmailTest < ActiveSupport::TestCase
        class FakeGmailService
          attr_accessor :authorization
          attr_reader :delivered_message

          def send_user_message(_user_id, message)
            @delivered_message = message
            Struct.new(:id).new("message-123")
          end
        end

        test "deliver sends encoded message" do
          authorization = Object.new
          service = FakeGmailService.new

          R3x::Client::GoogleAuth.require_gmail!
          R3x::GemLoader.require("mail")

          with_env("R3X_GMAIL_DRY_RUN" => "false") do
            R3x::Client::GoogleAuth.expects(:require_gmail!)
            R3x::Client::GoogleAuth.stubs(:from_env).with(project: "TEST_APP", scope: "gmail.send").returns(authorization)
            R3x::GemLoader.expects(:require).with("mail")
            ::Google::Apis::GmailV1::GmailService.stubs(:new).returns(service)

            result = Gmail.new(project: "TEST_APP").deliver(
              to: "recipient@example.com",
              subject: "Hello",
              body: "Body"
            )

            assert_equal authorization, service.authorization
            assert_equal({ "mode" => "real", "message_id" => "message-123" }, result)
            assert_includes service.delivered_message.raw, "To: recipient@example.com"
            assert_includes service.delivered_message.raw, "Subject: Hello"
            assert_includes service.delivered_message.raw, "Body"
          end
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
      end
    end
  end
end

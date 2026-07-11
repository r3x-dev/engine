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
              body: "Body",
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
            result = nil
            output = capture_logged_output do
              result = Gmail.new(project: "TEST_APP").deliver(
                to: "recipient@example.com",
                subject: "Hello",
                body: "Private plain body",
                html_body: "<p>Private HTML body</p>",
                attachments: [{ filename: "report.txt", content: "private attachment" }],
              )
            end

            assert_equal({ "mode" => "dry_run" }, result)
            assert_includes output, "DRY-RUN"
            assert_includes output, "action=deliver"
            assert_includes output, "to=recipient@example.com"
            assert_includes output, "subject=Hello"
            assert_includes output, "body_length=18"
            assert_includes output, "html_body_length=24"
            assert_includes output, 'body_preview=\"<p>Private HTML body</p>\"'
            assert_includes output, "attachments=1"
            assert_not_includes output, "private attachment"
          end
        end

        test "deliver sends multipart alternative message with html body" do
          service = FakeGmailService.new

          with_env("R3X_GMAIL_DRY_RUN" => "false") do
            R3x::Client::GoogleAuth.require_gmail!
            R3x::Client::GoogleAuth.stubs(:from_env).returns(Object.new)
            ::Google::Apis::GmailV1::GmailService.stubs(:new).returns(service)

            Gmail.new(project: "TEST_APP").deliver(
              to: "recipient@example.com",
              subject: "Hello",
              body: "Plain body",
              html_body: "<p><a href=\"https://example.test\">HTML body</a></p>",
            )

            message = Mail.read_from_string(service.delivered_message.raw)

            assert_predicate message, :multipart?
            assert_equal "Plain body", message.text_part.decoded
            assert_includes message.html_part.decoded, "<a href=\"https://example.test\">HTML body</a>"
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

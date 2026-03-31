# frozen_string_literal: true

module R3x
  module Client
    module Google
      class Gmail
        include R3x::Concerns::Logger

        def initialize(credentials_env:)
          @credentials_env = credentials_env
        end

        def deliver(to:, subject:, body:)
          result = build_service.send_user_message(
            "me", # The user's email address. The special value `me` can be used to indicate the
            ::Google::Apis::GmailV1::Message.new(raw: raw_message(to: to, subject: subject, body: body))
          )

          {
            "mode" => "real",
            "message_id" => result.id
          }
        end

        private

        attr_reader :credentials_env

        def build_service
          ::Google::Apis::GmailV1::GmailService.new.tap do |service|
            service.authorization = R3x::Client::GoogleAuth.from_json(
              R3x::Client::Google::Credentials.from_env(credentials_env),
              scope: ::Google::Apis::GmailV1::AUTH_GMAIL_SEND
            )
          end
        end

        def raw_message(to:, subject:, body:)
          Mail.new.tap do |mail|
            mail.to = to
            mail.subject = subject
            mail.body = body
          end.to_s
        end
      end
    end
  end
end

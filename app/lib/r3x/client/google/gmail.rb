# frozen_string_literal: true

module R3x
  module Client
    module Google
      class Gmail
        include R3x::Concerns::Logger

        def initialize(project:)
          @project = project
        end

        def deliver(to:, subject:, body:, attachments: [])
          if R3x::Policy.dry_run_for(:gmail)
            logger.info "[DRY-RUN]: \nto: #{to}\nsubject: #{subject}\nbody: #{body}"

            return { "mode" => "dry_run" }
          end

          result = build_service.send_user_message(
            "me", # The user's email address. The special value `me` can be used to indicate the
            ::Google::Apis::GmailV1::Message.new(raw: raw_message(to: to, subject: subject, body: body, attachments: attachments))
          )

          {
            "mode" => "real",
            "message_id" => result.id
          }
        end

        private

        attr_reader :project

        def build_service
          R3x::Client::GoogleAuth.require_gmail!

          ::Google::Apis::GmailV1::GmailService.new.tap { |service| service.authorization = R3x::Client::GoogleAuth.from_env(project: project, scope: "gmail.send") }
        end

        def raw_message(to:, subject:, body:, attachments: [])
          R3x::GemLoader.require("mail")

          Mail.new.tap do |mail|
            mail.charset = "UTF-8"
            mail.to = to
            mail.subject = subject

            if attachments.any?
              mail.text_part = Mail::Part.new { body body }

              attachments.each { |attachment| mail.add_file(filename: attachment[:filename], content: attachment[:content]) }
            else
              mail.body = body
            end
          end.to_s
        end
      end
    end
  end
end

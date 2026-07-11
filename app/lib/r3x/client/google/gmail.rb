# frozen_string_literal: true

module R3x
  module Client
    module Google
      class Gmail
        include R3x::Concerns::Logger

        def initialize(project:)
          @project = project
        end

        def deliver(to:, subject:, body:, html_body: nil, attachments: [])
          if R3x::Policy.dry_run_for(:gmail)
            body_preview = (html_body.presence || body).to_s.first(200).inspect

            logger.info(
              "[DRY-RUN] action=deliver to=#{Array(to).join(',').squish} subject=#{subject.to_s.squish} " \
                "body_length=#{body.to_s.bytesize} html_body_length=#{html_body.to_s.bytesize} " \
                "body_preview=#{body_preview} attachments=#{attachments.size}",
            )

            return { "mode" => "dry_run" }
          end

          result = build_service.send_user_message(
            "me", # The user's email address. The special value `me` can be used to indicate the
            ::Google::Apis::GmailV1::Message.new(raw: raw_message(to:, subject:, body:, html_body:, attachments:)),
          )

          {
            "mode"       => "real",
            "message_id" => result.id,
          }
        end

        private

        attr_reader :project

        def build_service
          R3x::Client::GoogleAuth.require_gmail!

          ::Google::Apis::GmailV1::GmailService.new.tap { |service| service.authorization = R3x::Client::GoogleAuth.from_env(project:, scope: "gmail.send") }
        end

        def raw_message(to:, subject:, body:, html_body: nil, attachments: [])
          R3x::GemLoader.require("mail")

          Mail.new.tap do |mail|
            mail.charset = "UTF-8"
            mail.to = to
            mail.subject = subject

            if html_body.present?
              mail.text_part = Mail::Part.new do |part|
                part.content_type = "text/plain; charset=UTF-8"
                part.body = body
              end
              mail.html_part = Mail::Part.new do |part|
                part.content_type = "text/html; charset=UTF-8"
                part.body = html_body
              end
            elsif attachments.any?
              mail.text_part = Mail::Part.new do |part|
                part.content_type = "text/plain; charset=UTF-8"
                part.body = body
              end
            else
              mail.body = body
            end

            attachments.each { |attachment| mail.add_file(filename: attachment[:filename], content: attachment[:content]) }
          end.to_s
        end
      end
    end
  end
end

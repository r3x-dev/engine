# frozen_string_literal: true

module R3x
  module Client
    module GoogleAuth
      SCOPE_ALIASES = {
        "gmail.readonly" => ::Google::Apis::GmailV1::AUTH_GMAIL_READONLY,
        "gmail.send" => ::Google::Apis::GmailV1::AUTH_GMAIL_SEND,
        "gmail.compose" => ::Google::Apis::GmailV1::AUTH_GMAIL_COMPOSE,
        "gmail.modify" => ::Google::Apis::GmailV1::AUTH_GMAIL_MODIFY,
        "sheets.readonly" => ::Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY,
        "sheets" => ::Google::Apis::SheetsV4::AUTH_SPREADSHEETS,
        "calendar.readonly" => ::Google::Apis::CalendarV3::AUTH_CALENDAR_READONLY,
        "calendar" => ::Google::Apis::CalendarV3::AUTH_CALENDAR
      }.freeze

      def self.from_json(parsed_json, scope:)
        Signet::OAuth2::Client.new(
          client_id: parsed_json.fetch("client_id"),
          client_secret: parsed_json.fetch("client_secret"),
          refresh_token: parsed_json.fetch("refresh_token"),
          token_credential_uri: "https://oauth2.googleapis.com/token",
          scope: Array(scope)
        ).tap(&:fetch_access_token!)
      end

      def self.resolve_scope(alias_or_scope)
        key = alias_or_scope.to_s
        SCOPE_ALIASES.fetch(key) { |k| k }
      end
    end
  end
end

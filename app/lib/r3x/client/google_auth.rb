# frozen_string_literal: true

module R3x
  module Client
    module GoogleAuth
      GMAIL_SCOPE_ALIASES = {
        "gmail.readonly" => "AUTH_GMAIL_READONLY",
        "gmail.send" => "AUTH_GMAIL_SEND",
        "gmail.compose" => "AUTH_GMAIL_COMPOSE",
        "gmail.modify" => "AUTH_GMAIL_MODIFY"
      }.freeze

      SHEETS_SCOPE_ALIASES = {
        "sheets.readonly" => "AUTH_SPREADSHEETS_READONLY",
        "sheets" => "AUTH_SPREADSHEETS"
      }.freeze

      CALENDAR_SCOPE_ALIASES = {
        "calendar.readonly" => "AUTH_CALENDAR_READONLY",
        "calendar" => "AUTH_CALENDAR"
      }.freeze

      def self.scope_aliases
        gmail_scope_aliases.merge(sheets_scope_aliases).merge(calendar_scope_aliases)
      end

      def self.from_json(parsed_json, scope:)
        require_googleauth!

        Signet::OAuth2::Client.new(
          client_id: parsed_json.fetch("client_id"),
          client_secret: parsed_json.fetch("client_secret"),
          refresh_token: parsed_json.fetch("refresh_token"),
          token_credential_uri: "https://oauth2.googleapis.com/token",
          scope: Array(scope).map { |value| resolve_scope(value) }
        ).tap(&:fetch_access_token!)
      end

      def self.resolve_scope(alias_or_scope)
        key = alias_or_scope.to_s
        case key
        when *gmail_scope_aliases.keys
          require_gmail!
          ::Google::Apis::GmailV1.const_get(gmail_scope_aliases.fetch(key))
        when *sheets_scope_aliases.keys
          require_sheets!
          ::Google::Apis::SheetsV4.const_get(sheets_scope_aliases.fetch(key))
        when *calendar_scope_aliases.keys
          require_calendar!
          ::Google::Apis::CalendarV3.const_get(calendar_scope_aliases.fetch(key))
        else
          key
        end
      end

      def self.require_gmail!
        R3x::GemLoader.require("google/apis/gmail_v1")
      end

      def self.require_googleauth!
        R3x::GemLoader.require("googleauth")
      end

      def self.require_sheets!
        R3x::GemLoader.require("google/apis/sheets_v4")
      end

      def self.require_calendar!
        R3x::GemLoader.require("google/apis/calendar_v3")
      end

      def self.gmail_scope_aliases
        GMAIL_SCOPE_ALIASES
      end

      def self.sheets_scope_aliases
        SHEETS_SCOPE_ALIASES
      end

      def self.calendar_scope_aliases
        CALENDAR_SCOPE_ALIASES
      end
    end
  end
end

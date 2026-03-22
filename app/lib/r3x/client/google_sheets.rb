# frozen_string_literal: true

module R3x
  module Client
    class GoogleSheets
      def initialize(spreadsheet_id:, credentials:)
        @spreadsheet_id = spreadsheet_id
        @credentials = credentials
        @service = build_service
      end

      def read_rows(range:, headers: true)
        response = service.get_spreadsheet_values(spreadsheet_id, range)
        rows = response.values || []
        return [] if rows.empty?

        return rows unless headers

        header_row = rows.first
        unique_headers = make_unique_headers(header_row)
        data_rows = rows.drop(1)

        data_rows.map { |row| row_to_hash(unique_headers, row) }
      end

      private

      attr_reader :spreadsheet_id, :credentials, :service

      def build_service
        service = Google::Apis::SheetsV4::SheetsService.new
        service.authorization = R3x::Client::GoogleAuth.from_json(
          credentials,
          scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
        )
        service
      end

      def make_unique_headers(headers)
        seen = Hash.new(0)
        headers.map do |header|
          seen[header] += 1
          (seen[header] > 1) ? "#{header}_#{seen[header]}" : header
        end
      end

      def row_to_hash(headers, row)
        padded_row = row + Array.new([ 0, headers.length - row.length ].max, nil)
        headers.zip(padded_row).to_h
      end
    end
  end
end

# frozen_string_literal: true

module R3x
  module Client
    class GoogleSheets
      def initialize(spreadsheet_id:, project:)
        @spreadsheet_id = spreadsheet_id
        @project = project
        @service = build_service
      end

      def read_rows(range:, as_hashes: false)
        response = service.get_spreadsheet_values(spreadsheet_id, range)
        rows = response.values || []
        return [] if rows.empty?

        return rows unless as_hashes

        header_row = rows.first
        validate_headers!(header_row)
        data_rows = rows.drop(1)

        data_rows.map { |row| row_to_hash(header_row, row) }
      end

      private

      attr_reader :spreadsheet_id, :project, :service

      def build_service
        R3x::Client::GoogleAuth.require_sheets!

        service = ::Google::Apis::SheetsV4::SheetsService.new
        service.authorization = R3x::Client::GoogleAuth.from_env(project:, scope: "sheets.readonly")
        service
      end

      def validate_headers!(headers)
        if headers.empty? || headers.any?(&:blank?) || headers.uniq.size != headers.size
          raise ArgumentError, "Google Sheets headers must be nonblank and unique; fix the sheet or use as_hashes: false"
        end
      end

      def row_to_hash(headers, row)
        if row.size > headers.size
          raise ArgumentError, "Google Sheets row has more cells than headers; fix the sheet or use as_hashes: false"
        end

        headers.zip(row).to_h
      end
    end
  end
end

# frozen_string_literal: true

module R3x
  module Client
    module GoogleSheets
      class Client
        def initialize(spreadsheet_id:, credentials:)
          @spreadsheet_id = spreadsheet_id
          @credentials = credentials
          @service = build_service
        end

        def read_rows(range:)
          response = service.get_spreadsheet_values(spreadsheet_id, range)
          rows = response.values || []
          return [] if rows.empty?

          headers = rows.first
          rows.drop(1).map { |row| headers.zip(row).to_h }
        end

        private

        attr_reader :spreadsheet_id, :credentials, :service

        def build_service
          service = Google::Apis::SheetsV4::SheetsService.new
          service.authorization = GoogleAuth.from_json(
            credentials,
            scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
          )
          service
        end
      end
    end
  end
end

require "test_helper"

module R3x
  module Client
    class GoogleSheetsTest < ActiveSupport::TestCase
      test "read_rows returns hashes keyed by header row" do
        service = fake_service_with_rows([
          [ "Name", "Email" ],
          [ "Ada", "ada@example.com" ],
          [ "Linus", "linus@example.com" ]
        ])

        with_stubbed_google_sheets_service(service) do
          rows = GoogleSheets.new(
            spreadsheet_id: "spreadsheet-123",
            credentials_env: "GOOGLE_CREDENTIALS_TEST_APP"
          ).read_rows(range: "Sheet1!A:B")

          assert_equal(
            [
              { "Name" => "Ada", "Email" => "ada@example.com" },
              { "Name" => "Linus", "Email" => "linus@example.com" }
            ],
            rows
          )
          assert_equal [ "spreadsheet-123", "Sheet1!A:B" ], service.calls.first
        end
      end

      test "read_rows returns raw rows when headers are disabled" do
        service = fake_service_with_rows([
          [ "Name", "Email" ],
          [ "Ada", "ada@example.com" ]
        ])

        with_stubbed_google_sheets_service(service) do
          rows = GoogleSheets.new(
            spreadsheet_id: "spreadsheet-123",
            credentials_env: "GOOGLE_CREDENTIALS_TEST_APP"
          ).read_rows(range: "Sheet1!A:B", headers: false)

          assert_equal(
            [
              [ "Name", "Email" ],
              [ "Ada", "ada@example.com" ]
            ],
            rows
          )
        end
      end

      test "read_rows deduplicates headers and pads short rows" do
        service = fake_service_with_rows([
          [ "Name", "Name", "Email" ],
          [ "Ada", "Lovelace" ]
        ])

        with_stubbed_google_sheets_service(service) do
          rows = GoogleSheets.new(
            spreadsheet_id: "spreadsheet-123",
            credentials_env: "GOOGLE_CREDENTIALS_TEST_APP"
          ).read_rows(range: "Sheet1!A:C")

          assert_equal(
            [
              { "Name" => "Ada", "Name_2" => "Lovelace", "Email" => nil }
            ],
            rows
          )
        end
      end

      test "read_rows returns empty array when the sheet is empty" do
        service = fake_service_with_rows(nil)

        with_stubbed_google_sheets_service(service) do
          rows = GoogleSheets.new(
            spreadsheet_id: "spreadsheet-123",
            credentials_env: "GOOGLE_CREDENTIALS_TEST_APP"
          ).read_rows(range: "Sheet1!A:C")

          assert_equal [], rows
        end
      end

      private

      def fake_service_with_rows(rows)
        Struct.new(:calls, :values) do
          def get_spreadsheet_values(spreadsheet_id, range)
            calls << [ spreadsheet_id, range ]
            Struct.new(:values).new(values)
          end
        end.new([], rows)
      end

      def with_stubbed_google_sheets_service(result)
        original_method = GoogleSheets.instance_method(:build_service)

        GoogleSheets.class_eval do
          define_method(:build_service) { result }
          private :build_service
        end

        yield
      ensure
        GoogleSheets.class_eval do
          define_method(:build_service, original_method)
          private :build_service
        end
      end
    end
  end
end

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

        GoogleSheets.any_instance.stubs(:build_service).returns(service)

        rows = GoogleSheets.new(
          spreadsheet_id: "spreadsheet-123",
          project: "TEST_APP"
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

      test "read_rows returns raw rows when headers are disabled" do
        service = fake_service_with_rows([
          [ "Name", "Email" ],
          [ "Ada", "ada@example.com" ]
        ])

        GoogleSheets.any_instance.stubs(:build_service).returns(service)

        rows = GoogleSheets.new(
          spreadsheet_id: "spreadsheet-123",
          project: "TEST_APP"
        ).read_rows(range: "Sheet1!A:B", headers: false)

        assert_equal(
          [
            [ "Name", "Email" ],
            [ "Ada", "ada@example.com" ]
          ],
          rows
        )
      end

      test "read_rows deduplicates headers and pads short rows" do
        service = fake_service_with_rows([
          [ "Name", "Name", "Email" ],
          [ "Ada", "Lovelace" ]
        ])

        GoogleSheets.any_instance.stubs(:build_service).returns(service)

        rows = GoogleSheets.new(
          spreadsheet_id: "spreadsheet-123",
          project: "TEST_APP"
        ).read_rows(range: "Sheet1!A:C")

        assert_equal(
          [
            { "Name" => "Ada", "Name_2" => "Lovelace", "Email" => nil }
          ],
          rows
        )
      end

      test "read_rows returns empty array when the sheet is empty" do
        service = fake_service_with_rows(nil)

        GoogleSheets.any_instance.stubs(:build_service).returns(service)

        rows = GoogleSheets.new(
          spreadsheet_id: "spreadsheet-123",
          project: "TEST_APP"
        ).read_rows(range: "Sheet1!A:C")

        assert_equal [], rows
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
    end
  end
end

# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class GoogleSheetsTest < ActiveSupport::TestCase
      test "read_rows returns hashes keyed by header row" do
        service = fake_service_with_rows([
          ["Name", "Email"],
          ["Ada", "ada@example.com"],
          ["Linus", "linus@example.com"],
        ])

        GoogleSheets.any_instance.stubs(:build_service).returns(service)

        rows = GoogleSheets.new(
          spreadsheet_id: "spreadsheet-123",
          project: "TEST_APP",
        ).read_rows(range: "Sheet1!A:B", as_hashes: true)

        assert_equal(
          [
            { "Name" => "Ada", "Email" => "ada@example.com" },
            { "Name" => "Linus", "Email" => "linus@example.com" },
          ],
          rows,
        )
        assert_equal ["spreadsheet-123", "Sheet1!A:B"], service.calls.first
      end

      test "read_rows returns raw rows by default" do
        service = fake_service_with_rows([
          ["Name", "Email"],
          ["Ada", "ada@example.com"],
        ])

        GoogleSheets.any_instance.stubs(:build_service).returns(service)

        rows = GoogleSheets.new(
          spreadsheet_id: "spreadsheet-123",
          project: "TEST_APP",
        ).read_rows(range: "Sheet1!A:B")

        assert_equal(
          [
            ["Name", "Email"],
            ["Ada", "ada@example.com"],
          ],
          rows,
        )
      end

      test "read_rows pads short rows" do
        service = fake_service_with_rows([
          %w[Name Surname Email],
          %w[Ada Lovelace],
        ])

        GoogleSheets.any_instance.stubs(:build_service).returns(service)

        rows = GoogleSheets.new(
          spreadsheet_id: "spreadsheet-123",
          project: "TEST_APP",
        ).read_rows(range: "Sheet1!A:C", as_hashes: true)

        assert_equal(
          [
            { "Name" => "Ada", "Surname" => "Lovelace", "Email" => nil },
          ],
          rows,
        )
      end

      test "read_rows returns empty array when the sheet is empty" do
        service = fake_service_with_rows(nil)

        GoogleSheets.any_instance.stubs(:build_service).returns(service)

        rows = GoogleSheets.new(
          spreadsheet_id: "spreadsheet-123",
          project: "TEST_APP",
        ).read_rows(range: "Sheet1!A:C")

        assert_equal [], rows
      end

      [[], [""], [nil], [" "], %w[Name Name], %w[Name Name Name_2]].each do |headers|
        test "read_rows rejects invalid headers #{headers.inspect}" do
          service = fake_service_with_rows([headers, ["value"]])
          GoogleSheets.any_instance.stubs(:build_service).returns(service)
          client = GoogleSheets.new(spreadsheet_id: "spreadsheet-123", project: "TEST_APP")

          error = assert_raises(ArgumentError) { client.read_rows(range: "Sheet1!A:C", as_hashes: true) }

          assert_includes error.message, "headers must be nonblank and unique"
          assert_includes error.message, "as_hashes: false"
        end
      end

      test "read_rows rejects data beyond the header row" do
        service = fake_service_with_rows([
          ["Name"],
          ["Ada"],
          %w[Linus second third],
          [],
        ])
        GoogleSheets.any_instance.stubs(:build_service).returns(service)

        client = GoogleSheets.new(spreadsheet_id: "spreadsheet-123", project: "TEST_APP")

        error = assert_raises(ArgumentError) { client.read_rows(range: "Sheet1!A:C", as_hashes: true) }

        assert_includes error.message, "more cells than headers"
        assert_includes error.message, "as_hashes: false"
      end

      test "read_rows preserves original names including suffixes" do
        service = fake_service_with_rows([%w[Name Name_2], %w[first second]])
        GoogleSheets.any_instance.stubs(:build_service).returns(service)

        rows = GoogleSheets.new(spreadsheet_id: "spreadsheet-123", project: "TEST_APP").read_rows(range: "Sheet1!A:B", as_hashes: true)

        assert_equal [{ "Name" => "first", "Name_2" => "second" }], rows
      end

      test "raw rows allow blank duplicate and missing headers" do
        raw_rows = [["Name", "Name", ""], %w[first second third fourth]]
        service = fake_service_with_rows(raw_rows)
        GoogleSheets.any_instance.stubs(:build_service).returns(service)
        client = GoogleSheets.new(spreadsheet_id: "spreadsheet-123", project: "TEST_APP")

        assert_equal raw_rows, client.read_rows(range: "Sheet1!A:D", as_hashes: false)
      end

      private

      def fake_service_with_rows(rows)
        Struct.new(:calls, :values) do
          def get_spreadsheet_values(spreadsheet_id, range)
            calls << [spreadsheet_id, range]
            Struct.new(:values).new(values)
          end
        end.new([], rows)
      end
    end
  end
end

require "test_helper"

module R3x
  module Client
    class OcrTest < ActiveSupport::TestCase
      setup do
        @original_key = ENV["OCRSPACE_API_KEY"]
        ENV["OCRSPACE_API_KEY"] = "test-api-key"
      end

      teardown do
        ENV["OCRSPACE_API_KEY"] = @original_key
        WebMock.reset!
      end

      test "raises when OCRSPACE_API_KEY is missing" do
        ENV.delete("OCRSPACE_API_KEY")

        error = assert_raises(ArgumentError) do
          Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        end

        assert_equal "Missing OCRSPACE_API_KEY", error.message
      end

      test "raises when OCRSPACE_API_KEY is blank" do
        ENV["OCRSPACE_API_KEY"] = ""

        error = assert_raises(ArgumentError) do
          Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        end

        assert_equal "Missing OCRSPACE_API_KEY", error.message
      end

      test "raises when api_key_env does not start with OCRSPACE_API_KEY" do
        error = assert_raises(ArgumentError) do
          Ocr.new(api_key_env: "SOME_OTHER_KEY")
        end

        assert_equal "Key 'SOME_OTHER_KEY' must start with 'OCRSPACE_API_KEY'", error.message
      end

      test "accepts custom api_key_env with OCRSPACE_API_KEY prefix" do
        ENV["OCRSPACE_API_KEY_CUSTOM"] = "custom-key"

        stub_success("hello")

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY_CUSTOM")
        result = client.parse(StringIO.new("fake"), filetype: "image/jpeg")

        assert_equal "hello", result.text
      end

      test "parse with IO object sends base64 encoded image" do
        stub_success("Extracted text")

        io = StringIO.new("fake image data")
        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        result = client.parse(io, filetype: "image/jpeg")

        assert_equal "Extracted text", result.text
        assert_requested :post, "https://api.ocr.space/parse/image",
          headers: { "Apikey" => "test-api-key" }
      end

      test "parse with IO requires filetype" do
        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")

        error = assert_raises(ArgumentError) do
          client.parse(StringIO.new("data"))
        end

        assert_equal "filetype required for IO objects (e.g. filetype: 'image/jpeg')", error.message
      end

      test "parse with file path auto-detects MIME type" do
        stub_success("File text")

        tempfile = Tempfile.new([ "test", ".png" ])
        tempfile.write("fake png data")
        tempfile.rewind

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        result = client.parse(tempfile.path)

        assert_equal "File text", result.text
      ensure
        tempfile&.close
        tempfile&.unlink
      end

      test "parse with unsupported extension raises" do
        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")

        error = assert_raises(ArgumentError) do
          client.parse("/tmp/file.xyz")
        end

        assert_match "Unsupported file extension: '.xyz'", error.message
      end

      test "parse passes language parameter" do
        stub_success("Polski tekst")

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        result = client.parse(StringIO.new("data"), filetype: "image/jpeg", language: "pol")

        assert_equal "Polski tekst", result.text
      end

      test "parse passes engine parameter" do
        stub_success("Engine 2 text")

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        result = client.parse(StringIO.new("data"), filetype: "image/jpeg", engine: 2)

        assert_equal "Engine 2 text", result.text
      end

      test "parse passes overlay parameter" do
        stub_success("Overlay text")

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        result = client.parse(StringIO.new("data"), filetype: "image/jpeg", overlay: true)

        assert_equal "Overlay text", result.text
      end

      test "parse raises on HTTP error" do
        stub_request(:post, "https://api.ocr.space/parse/image")
          .to_return(status: 500, body: "internal error")

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")

        error = assert_raises(RuntimeError) do
          client.parse(StringIO.new("data"), filetype: "image/jpeg")
        end

        assert_equal "OCR request failed: 500", error.message
      end

      test "parse raises on API error" do
        stub_request(:post, "https://api.ocr.space/parse/image")
          .to_return(
            status: 200,
            body: {
              IsErroredOnProcessing: true,
              ErrorMessage: "Invalid image format",
              OCRExitCode: "4"
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")

        error = assert_raises(RuntimeError) do
          client.parse(StringIO.new("data"), filetype: "image/jpeg")
        end

        assert_equal "OCR API error: Invalid image format", error.message
      end

      test "result success? returns true when exit code is 1" do
        stub_success("ok")

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        result = client.parse(StringIO.new("data"), filetype: "image/jpeg")

        assert result.success?
      end

      test "result partial? returns true when exit code is 2" do
        stub_request(:post, "https://api.ocr.space/parse/image")
          .to_return(
            status: 200,
            body: {
              ParsedResults: [
                { ParsedText: "page 1", FileParseExitCode: "1" },
                { ParsedText: "page 2", FileParseExitCode: "1" }
              ],
              OCRExitCode: "2",
              IsErroredOnProcessing: false,
              ProcessingTimeInMilliseconds: "1500"
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        result = client.parse(StringIO.new("data"), filetype: "image/jpeg")

        assert result.partial?
        assert_equal "page 1\npage 2", result.text
        assert_equal 1500, result.processing_time_ms
      end

      test "result is enumerable over pages" do
        stub_request(:post, "https://api.ocr.space/parse/image")
          .to_return(
            status: 200,
            body: {
              ParsedResults: [
                { ParsedText: "page 1", FileParseExitCode: "1" },
                { ParsedText: "page 2", FileParseExitCode: "1" }
              ],
              OCRExitCode: "1",
              IsErroredOnProcessing: false
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        result = client.parse(StringIO.new("data"), filetype: "image/jpeg")

        assert_equal 2, result.count
        assert_equal "page 1", result.first.text
        assert_equal "page 2", result.to_a.last.text
      end

      test "page success? returns true for successful parse" do
        stub_success("ok")

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        result = client.parse(StringIO.new("data"), filetype: "image/jpeg")

        assert result.first.success?
        assert_nil result.first.error_message
      end

      test "page exposes error details" do
        stub_request(:post, "https://api.ocr.space/parse/image")
          .to_return(
            status: 200,
            body: {
              ParsedResults: [
                {
                  ParsedText: "",
                  FileParseExitCode: "-10",
                  ErrorMessage: "OCR Engine Error",
                  ErrorDetails: "Could not process image"
                }
              ],
              OCRExitCode: "3",
              IsErroredOnProcessing: false
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        client = Ocr.new(api_key_env: "OCRSPACE_API_KEY")
        result = client.parse(StringIO.new("data"), filetype: "image/jpeg")

        refute result.first.success?
        assert_equal "OCR Engine Error", result.first.error_message
        assert_equal "Could not process image", result.first.error_details
      end

      private

      def stub_success(parsed_text)
        stub_request(:post, "https://api.ocr.space/parse/image")
          .to_return(
            status: 200,
            body: {
              ParsedResults: [
                { ParsedText: parsed_text, FileParseExitCode: "1" }
              ],
              OCRExitCode: "1",
              IsErroredOnProcessing: false,
              ProcessingTimeInMilliseconds: "500"
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end
    end
  end
end

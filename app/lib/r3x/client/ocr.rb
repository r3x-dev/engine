# frozen_string_literal: true

require "base64"

module R3x
  module Client
    class Ocr
      ENDPOINT = "parse/image"
      BASE_URL = "https://api.ocr.space"

      MIME_TYPES = {
        ".png"  => "image/png",
        ".jpg"  => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".gif"  => "image/gif",
        ".tif"  => "image/tiff",
        ".tiff" => "image/tiff",
        ".bmp"  => "image/bmp",
        ".pdf"  => "application/pdf"
      }.freeze

      def initialize(api_key_env:)
        @api_key = R3x::Env.secure_fetch(api_key_env, prefix: "OCRSPACE_API_KEY")
      end

      def parse(io_or_path, language: nil, engine: nil, filetype: nil, overlay: false)
        mime_type = filetype || detect_mime(io_or_path)
        params = build_params(io_or_path, mime_type, language: language, engine: engine, overlay: overlay)
        response = connection.post(ENDPOINT, params)
        raise "OCR request failed: #{response.status}" unless response.success?

        body = response.body
        raise "OCR API error: #{body["ErrorMessage"]}" if body["IsErroredOnProcessing"]

        Result.new(body)
      end

      private

      attr_reader :api_key

      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :url_encoded
          f.response :json
          f.options.timeout = 30
          f.options.open_timeout = 5
          f.headers["apikey"] = api_key
        end
      end

      def detect_mime(io_or_path)
        if io_or_path.respond_to?(:read)
          raise ArgumentError, "filetype required for IO objects (e.g. filetype: 'image/jpeg')"
        end

        if binary_string?(io_or_path)
          raise ArgumentError, "filetype required for raw binary image data (e.g. filetype: 'image/jpeg')"
        end

        ext = File.extname(io_or_path.to_s).downcase
        MIME_TYPES.fetch(ext) do
          raise ArgumentError, "Unsupported file extension: '#{ext}'. Pass filetype: explicitly."
        end
      end

      def build_params(io_or_path, mime_type, language:, engine:, overlay:)
        params = {
          isOverlayRequired: overlay.to_s
        }
        params[:language] = language if language
        params[:OCREngine] = engine.to_s if engine

        raw = if io_or_path.respond_to?(:read)
          io_or_path.read
        elsif binary_string?(io_or_path)
          io_or_path
        else
          File.binread(io_or_path.to_s)
        end
        encoded = Base64.strict_encode64(raw)
        params[:base64Image] = "data:#{mime_type};base64,#{encoded}"

        params
      end

      def binary_string?(value)
        value.is_a?(String) && (value.encoding == Encoding::BINARY || value.bytes.include?(0))
      end
    end
  end
end

# frozen_string_literal: true

require "faraday/multipart"

module R3x
  module Client
    class Http
      def initialize(verify_ssl: true, timeout: 10)
        @verify_ssl = verify_ssl
        @timeout = timeout
      end

      def get(url, params: {}, headers: {})
        connection.get(url, params, headers)
      end

      def head(url, params: {}, headers: {})
        connection.head(url, params, headers)
      end

      def post(url, payload, headers: {})
        connection.post(url, payload, headers)
      end

      def download_file(url, headers: {})
        response = connection.get(url, {}, headers)

        DownloadedFile.new(
          body: response.body,
          content_type: response.headers["Content-Type"]&.split(";")&.first,
          filename: filename_from_headers(response.headers),
          url: url
        )
      end

      def upload_file(url, file, file_field: "file", filename: nil, content_type: nil, params: {}, headers: {})
        file_io = file.respond_to?(:read) ? file : StringIO.new(file.dup)
        original_position = file_io.pos if file_io.respond_to?(:pos)
        file_content_type = content_type || sniff_content_type(file_io)
        rewind_file(file_io)

        file_part = ::Faraday::Multipart::FilePart.new(file_io, file_content_type, filename)

        payload = params.merge(file_field => file_part)

        connection.tap do |conn|
          conn.request :multipart
          conn.request :url_encoded
        end.post(url, payload, headers)
      ensure
        restore_file_position(file_io, original_position)
      end

      private

      attr_reader :verify_ssl, :timeout

      def connection
        Faraday.new(ssl: { verify: verify_ssl }, request: { timeout: timeout }) do |f|
          f.response :raise_error
        end
      end

      def filename_from_headers(headers)
        disposition = headers["Content-Disposition"]
        return nil unless disposition

        filename_star_from_disposition(disposition) ||
          disposition.match(/filename=["']?([^"';]+)["']?/i)&.captures&.first
      end

      def filename_star_from_disposition(disposition)
        encoded_filename = disposition.match(/filename\*\s*=\s*([^;]+)/i)&.captures&.first
        return nil unless encoded_filename

        value = encoded_filename.strip.delete_prefix('"').delete_suffix('"')
        charset, _, encoded_value = value.split("'", 3)
        encoded_value ||= value

        decode_percent_encoded_value(encoded_value, charset)
      rescue ArgumentError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        decode_percent_encoded_value(encoded_value || value)
      end

      def sniff_content_type(file_io)
        R3x::GemLoader.require("marcel")

        position = file_io.pos if file_io.respond_to?(:pos)

        ::Marcel::MimeType.for(file_io)
      ensure
        restore_file_position(file_io, position)
      end

      def restore_file_position(file_io, position = nil)
        return unless position && file_io.respond_to?(:seek)

        file_io.seek(position)
      rescue StandardError
        nil
      end

      def rewind_file(file_io)
        file_io.rewind if file_io.respond_to?(:rewind)
      rescue StandardError
        nil
      end

      def decode_percent_encoded_value(value, charset = "UTF-8")
        URI::DEFAULT_PARSER.unescape(value)
          .force_encoding(Encoding.find(charset || "UTF-8"))
          .encode(Encoding::UTF_8)
      end
    end
  end
end

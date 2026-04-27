# frozen_string_literal: true

module R3x
  module Client
    class Http
      def initialize(verify_ssl: true, timeout: 10)
        ssl_options = verify_ssl ? {} : { verify_mode: OpenSSL::SSL::VERIFY_NONE }
        @client = HTTPX.with(
          timeout: { connect_timeout: 5, operation_timeout: timeout },
          ssl: ssl_options
        )
      end

      def get(url, params: {}, headers: {})
        @client.get(url, params: params, headers: headers).raise_for_status
      end

      def head(url, params: {}, headers: {})
        @client.head(url, params: params, headers: headers).raise_for_status
      end

      def post(url, payload, headers: {})
        @client.post(url, json: payload, headers: headers).raise_for_status
      end

      def download_file(url, headers: {})
        response = @client.get(url, headers: headers).raise_for_status

        DownloadedFile.new(
          body: response.body.to_s,
          content_type: response.headers["content-type"]&.split(";")&.first,
          filename: filename_from_headers(response.headers),
          url: url
        )
      end

      def upload_file(url, file, file_field: "file", filename: nil, content_type: nil, params: {}, headers: {})
        file_io = file.respond_to?(:read) ? file : StringIO.new(file.to_s)
        original_position = file_io.pos if file_io.respond_to?(:pos)

        # httpx properly serializes File objects as multipart; StringIO is sent as-is.
        # Convert to a Tempfile so filename and content-type are preserved.
        upload_io = if file_io.respond_to?(:path)
          file_io
        else
          temp = Tempfile.new([ filename || "upload", nil ])
          temp.binmode
          temp.write(file_io.read)
          temp.rewind
          temp
        end

        file_value = {
          body: upload_io,
          filename: filename || "file",
          content_type: content_type || "application/octet-stream"
        }

        payload = params.merge(file_field => file_value)

        @client.post(url, form: payload, headers: headers).raise_for_status
      ensure
        if defined?(temp) && temp
          temp.close
          temp.unlink
        end
        restore_file_position(file_io, original_position)
      end

      private

      attr_reader :verify_ssl, :timeout

      def filename_from_headers(headers)
        disposition = headers["content-disposition"]
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

      def restore_file_position(file_io, position = nil)
        return unless position && file_io.respond_to?(:seek)

        file_io.seek(position)
      rescue
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

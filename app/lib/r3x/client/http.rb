# frozen_string_literal: true

module R3x
  module Client
    class Http
      class << self
        def with_persistence(verify_ssl: true, timeout: nil)
          session = HTTPX.plugin(:persistent, close_on_fork: true)
          opts = httpx_options(verify_ssl:, timeout:)
          session = session.with(**opts) if opts.any?

          session.wrap do |client|
            http = allocate
            http.instance_variable_set(:@client, client)

            yield http
          end
        end

        private

        def httpx_options(verify_ssl:, timeout:)
          opts = {}
          opts[:timeout] = { operation_timeout: timeout } if timeout
          opts[:ssl] = { verify_mode: OpenSSL::SSL::VERIFY_NONE } unless verify_ssl
          opts
        end
      end

      def initialize(verify_ssl: true, timeout: nil)
        # Keep option building private to this class while sharing it with the class-level persistence path.
        opts = self.class.send(:httpx_options, verify_ssl:, timeout:)
        @client = opts.any? ? HTTPX.with(**opts) : HTTPX
      end

      def get(url, params: {}, headers: {})
        @client.get(url, params:, headers:).raise_for_status
      end

      def head(url, params: {}, headers: {})
        @client.head(url, params:, headers:).raise_for_status
      end

      def post(url, payload, headers: {})
        @client.post(url, json: payload, headers:).raise_for_status
      end

      def download_file(url, headers: {})
        response = @client.get(url, headers:).raise_for_status

        content_type = response.headers["content-type"]&.split(";")&.first
        filename = response.body.filename || filename_from_url(url, content_type:)

        DownloadedFile.new(body: response.body.to_s, content_type:, filename:, url:)
      end

      def upload_file(url, file, file_field: "file", filename: nil, content_type: nil, params: {}, headers: {})
        file_io = file.respond_to?(:read) ? file : StringIO.new(file.to_s)
        original_position = file_io.pos if file_io.respond_to?(:pos)
        file_content_type = content_type || sniff_content_type(file_io)
        rewind_file(file_io)

        actual_filename = filename || default_filename(file_io)

        # httpx properly serializes File objects as multipart; StringIO is sent as-is.
        # Convert to a Tempfile so filename and content-type are preserved.
        upload_io = if file_io.respond_to?(:path)
          file_io
        else
          temp = Tempfile.new([actual_filename || "upload", nil])
          temp.binmode
          temp.write(file_io.read)
          temp.rewind
          temp
        end

        file_value = { body: upload_io, filename: actual_filename || "file", content_type: file_content_type || "application/octet-stream" }

        payload = params.merge(file_field => file_value)

        @client.post(url, form: payload, headers:).raise_for_status
      ensure
        if defined?(temp) && temp
          temp.close
          temp.unlink
        end
        restore_file_position(file_io, original_position)
      end

      private

      attr_reader :verify_ssl, :timeout

      def filename_from_url(url, content_type:)
        filename = File.basename(URI.parse(url).path)
        filename = "downloaded_file" if filename.empty? || filename == "/"

        extension = Rack::Mime::MIME_TYPES.invert[content_type] if content_type
        filename += extension if extension && File.extname(filename).empty?

        filename
      end

      def sniff_content_type(file_io)
        R3x::GemLoader.require("marcel")

        position = file_io.pos if file_io.respond_to?(:pos)

        ::Marcel::MimeType.for(file_io)
      ensure
        restore_file_position(file_io, position)
      end

      def default_filename(file_io)
        if file_io.respond_to?(:original_filename)
          file_io.original_filename
        elsif file_io.respond_to?(:path)
          File.basename(file_io.path)
        end
      end

      def rewind_file(file_io)
        file_io.rewind if file_io.respond_to?(:rewind)
      rescue
        nil
      end

      def restore_file_position(file_io, position = nil)
        return unless position && file_io.respond_to?(:seek)

        file_io.seek(position)
      rescue
        nil
      end
    end
  end
end

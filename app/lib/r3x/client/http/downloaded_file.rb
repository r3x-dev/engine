# frozen_string_literal: true

module R3x
  module Client
    class Http
      class DownloadedFile
        attr_reader :body, :content_type, :filename, :url

        def initialize(body:, content_type:, filename:, url:)
          @body = body
          @content_type = content_type
          @filename = filename
          @url = url
        end

        def to_io
          StringIO.new(body)
        end
      end
    end
  end
end

# frozen_string_literal: true

module R3x
  module Client
    class Ocr
      class Result
        include Enumerable

        def initialize(body)
          @body = body
          @pages = body.fetch("ParsedResults", []).map { |r| Page.new(r) }
        end

        def text
          pages.map(&:text).join("\n")
        end

        def success?
          exit_code == 1
        end

        def partial?
          exit_code == 2
        end

        def exit_code
          body["OCRExitCode"].to_i
        end

        def processing_time_ms
          body["ProcessingTimeInMilliseconds"]&.to_i
        end

        def each(&block)
          pages.each(&block)
        end

        private

        attr_reader :body, :pages

        Page = Struct.new(:data) do
          def text; data["ParsedText"]; end
          def success?; data["FileParseExitCode"].to_i == 1; end
          def error_message; data["ErrorMessage"]; end
          def error_details; data["ErrorDetails"]; end
        end
      end
    end
  end
end

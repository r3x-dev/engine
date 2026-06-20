# frozen_string_literal: true

module R3x
  module Dashboard
    class ErrorDetails
      ERROR_KEYS = %w[exception_class error_class message error backtrace trace stack].freeze

      def initialize(error)
        @error = error
      end

      def summary
        summary = if error.is_a?(Hash)
          parsed_error["message"] || parsed_error["error"] || error.inspect
        else
          extract_error_message(error.to_s)
        end

        summary.presence || "Unknown error"
      end

      def body
        return "No error details recorded." if error.blank?

        error.is_a?(Hash) ? error.inspect : error.to_s
      end

      def details_visible?
        body.present? && summary != body
      end

      def structured
        return if parsed_error.blank?

        {
          exception_class: parsed_error["exception_class"].presence || parsed_error["error_class"].presence,
          message: parsed_error["message"].presence || parsed_error["error"].presence,
          backtrace: Array(parsed_error["backtrace"] || parsed_error["trace"] || parsed_error["stack"]).compact_blank,
        }.compact_blank
      end

      private

      attr_reader :error

      def parsed_error
        @parsed_error ||=
          case error
          when Hash
            error.stringify_keys
          else
            parse_error_text(error.to_s) || {}
          end
      end

      def extract_error_message(text)
        first_line = text.lines.first.to_s.strip
        return Regexp.last_match(1) if first_line =~ /"message"\s*=>\s*"([^"]+)"/
        return Regexp.last_match(1) if first_line =~ /"message"\s*:\s*"([^"]+)"/

        first_line
      end

      def parse_error_text(text)
        return if text.blank?

        parse_json_error_text(text) || parse_ruby_hash_error_text(text)
      end

      def parse_json_error_text(text)
        return unless text.lstrip.start_with?("{", "[")

        parsed = MultiJSON.parse(text)
        parsed.is_a?(Hash) ? parsed.stringify_keys : nil
      rescue MultiJSON::ParseError
        nil
      end

      def parse_ruby_hash_error_text(text)
        return unless text.include?("=>")

        {
          "exception_class" => extract_ruby_hash_error_value(text, "exception_class"),
          "message"         => extract_ruby_hash_error_value(text, "message"),
          "backtrace"       => extract_ruby_hash_error_array(text, "backtrace"),
        }.compact_blank
      end

      def extract_ruby_hash_error_value(text, key)
        pattern = /
          "#{Regexp.escape(key)}"\s*(?:=>|:)\s*"(?<value>.*?)"\s*
          (?=,\s*"(?:#{ERROR_KEYS.join("|")})"\s*(?:=>|:)|\s*}\z)
        /mx
        match = text.match(pattern)
        return unless match

        unescape_error_string(match[:value])
      end

      def extract_ruby_hash_error_array(text, key)
        pattern = /
          "#{Regexp.escape(key)}"\s*(?:=>|:)\s*\[(?<value>.*?)\]\s*
          (?=,\s*"(?:#{ERROR_KEYS.join("|")})"\s*(?:=>|:)|\s*}\z)
        /mx
        match = text.match(pattern)
        return [] unless match

        match[:value]
          .scan(/"((?:[^"\\]|\\.)*)"/)
          .flatten
          .map { |value| unescape_error_string(value) }
      end

      def unescape_error_string(value)
        MultiJSON.parse(%("#{value}"))
      rescue MultiJSON::ParseError
        value.to_s.gsub('\"', '"').gsub("\\\\", "\\")
      end
    end
  end
end

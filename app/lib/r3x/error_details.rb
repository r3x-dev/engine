# frozen_string_literal: true

module R3x
  class ErrorDetails
    ERROR_KEYS = %w[exception_class error_class error_message message error backtrace trace stack].freeze

    attr_reader :error_class, :message, :backtrace

    def initialize(error)
      @error = error
      @parsed_error = parse_error
      @error_class = parsed_error["error_class"].presence || parsed_error["exception_class"].presence
      @message = parsed_error["message"].presence || parsed_error["error_message"].presence || parsed_error["error"].presence
      @backtrace = Array(parsed_error["backtrace"] || parsed_error["trace"] || parsed_error["stack"]).compact_blank.presence
    end

    def summary
      message.presence || fallback_summary.presence || "Unknown error"
    end

    def body
      return "No error details recorded." if error.blank?

      error.is_a?(Exception) ? exception_body : error.to_s
    end

    def details_visible?
      body.present? && summary != body
    end

    def structured
      {
        error_class:,
        message:,
        backtrace:,
      }.compact_blank.presence
    end

    private

    attr_reader :error, :parsed_error

    def parse_error
      case error
      when Exception
        {
          "error_class" => error.class.name,
          "message"     => error.message,
          "backtrace"   => error.backtrace,
        }
      when Hash
        error.stringify_keys
      else
        parse_error_text(error.to_s) || {}
      end
    end

    def fallback_summary
      case error
      when Hash
        error.inspect
      else
        first_line = error.to_s.lines.first.to_s.strip
        extract_error_value(first_line, "message") || extract_error_value(first_line, "error_message") || first_line
      end
    end

    def exception_body
      lines = ["#{error.class.name}: #{error.message}", *Array(error.backtrace)].compact_blank
      lines.join("\n")
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

      ERROR_KEYS.index_with { |key| extract_ruby_hash_error_value(text, key) }
        .merge(
          "backtrace" => extract_ruby_hash_error_array(text, "backtrace"),
          "trace"     => extract_ruby_hash_error_array(text, "trace"),
          "stack"     => extract_ruby_hash_error_array(text, "stack"),
        ).compact_blank
    end

    def extract_error_value(text, key)
      pattern = /"#{Regexp.escape(key)}"\s*(?:=>|:)\s*"([^"]+)"/
      match = text.match(pattern)
      match && unescape_error_string(match[1])
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

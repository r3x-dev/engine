require "logger"
require "multi_json"
require "time"

module R3x
  class LogFormatter < ::Logger::Formatter
    MODE_VALUES = %w[auto json text].freeze
    TAG_PATTERN = /\A(?:\[(?<tag>[^\]]+)\]\s*)+/

    def initialize(mode: ENV.fetch("R3X_LOG_FORMAT", "auto"), logs_provider: ENV["R3X_LOGS_PROVIDER"])
      @mode = normalize_mode(mode, logs_provider: logs_provider)
      super()
    end

    def call(severity, time, progname, msg)
      payload = payload_for(severity, time, progname, msg)

      case mode
      when :json
        MultiJson.dump(payload) << "\n"
      when :text
        format_text(payload)
      else
        raise ArgumentError, "Unsupported log formatter mode: #{mode.inspect}"
      end
    end

    private
      attr_reader :mode

      def normalize_mode(mode, logs_provider:)
        value = mode.to_s
        return :json if value == "auto" && logs_provider.to_s == "victorialogs"
        return :text if value == "auto"
        return value.to_sym if MODE_VALUES.include?(value)

        raise ArgumentError, "Unsupported R3X_LOG_FORMAT: #{mode.inspect}"
      end

      def payload_for(severity, time, progname, msg)
        message, tags = extract_message_and_tags(msg2str(msg))

        {
          "level" => normalize_level(severity),
          "message" => message,
          "time" => time.utc.iso8601(6)
        }.tap do |payload|
          payload["progname"] = progname if progname
          payload["tags"] = tags if tags.any?
        end
      end

      def normalize_level(severity)
        case severity.to_s.downcase
        when "any"
          "unknown"
        else
          severity.to_s.downcase
        end
      end

      def extract_message_and_tags(message)
        match = message.match(TAG_PATTERN)
        return [ message, [] ] unless match

        tags = match[0].scan(/\[([^\]]+)\]/).flatten
        stripped_message = message.delete_prefix(match[0]).strip

        [ stripped_message.empty? ? message : stripped_message, tags ]
      end

      def format_text(payload)
        parts = [ payload.fetch("time"), payload.fetch("level").upcase ]

        Array(payload["tags"]).each do |tag|
          parts << "[#{tag}]"
        end

        parts << payload.fetch("message").to_s.gsub(/\s+/, " ").strip
        parts.join(" ") << "\n"
      end
  end
end

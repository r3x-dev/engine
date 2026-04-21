require "logger"
require "multi_json"
require "time"

module R3x
  class LogFormatter < ::Logger::Formatter
    TAG_PATTERN = /\A(?:\[(?<tag>[^\]]+)\]\s*)+/

    def call(severity, time, progname, msg)
      payload = payload_for(severity, time, progname, msg)
      MultiJson.dump(payload) << "\n"
    end

    private

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
  end
end

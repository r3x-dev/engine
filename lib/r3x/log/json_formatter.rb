require "logger"
require "multi_json"
require "time"

module R3x
  class Log
    class JsonFormatter < ::Logger::Formatter
      def call(severity, time, progname, msg)
        payload = payload_for(severity, time, progname, msg)
        MultiJson.dump(payload) << "\n"
      end

      private

      def payload_for(severity, time, progname, msg)
        base = {
          "level" => normalize_level(severity),
          "time" => time.utc.iso8601(6)
        }
        base["progname"] = progname if progname

        case msg
        when Hash
          base.merge!(msg.transform_keys(&:to_s))
        when String, Symbol, NilClass
          message, tags = extract_message_and_tags(msg2str(msg))
          base["message"] = message
          base["tags"] = tags if tags.any?
        else
          raise ArgumentError, "Unsupported log message type: #{msg.class}"
        end

        base
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
        match = message.match(R3x::Log::TAG_PATTERN)
        return [ message, [] ] unless match

        tags = match[0].scan(/\[([^\]]+)\]/).flatten
        stripped_message = message.delete_prefix(match[0]).strip

        [ stripped_message.empty? ? message : stripped_message, tags ]
      end
    end
  end
end

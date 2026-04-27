module R3x
  class Log
    TAG_PATTERN = /\A(?:\[(?<tag>[^\]]+)\]\s+)+/

    def self.format
      @format ||= resolve_format
    end

    def self.json?
      format == "json"
    end

    def self.plain?
      !json?
    end

    def self.resolve_format
      format = ENV["R3X_LOG_FORMAT"].presence
      case format
      when nil, "plain"
        "plain"
      when "json"
        "json"
      else
        raise ArgumentError, "Unsupported R3X_LOG_FORMAT: #{format.inspect}. Use 'json' or 'plain'."
      end
    end
    private_class_method :resolve_format
  end
end

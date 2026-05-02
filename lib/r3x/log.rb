module R3x
  class Log
    TAG_PATTERN = /\A(?:\[(?<tag>[^\]]+)\]\s+)+/
    RUN_ACTIVE_JOB_ID_TAG = "r3x.run_active_job_id"
    TRIGGER_KEY_TAG = "r3x.trigger_key"
    WORKFLOW_KEY_TAG = "r3x.workflow_key"
    JOB_OUTCOME_TAG = "r3x.job_outcome"

    def self.tag(name, value)
      return if value.blank?

      "#{name}=#{value}"
    end

    def self.format
      resolve_format
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

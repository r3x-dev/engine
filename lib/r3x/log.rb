module R3x
  class Log
    TAG_PATTERN = /\A(?:\[(?<tag>[^\]]+)\]\s+)+/
    RUN_ACTIVE_JOB_ID_TAG = "r3x.run_active_job_id".freeze
    TRIGGER_KEY_TAG = "r3x.trigger_key".freeze
    WORKFLOW_KEY_TAG = "r3x.workflow_key".freeze
    JOB_OUTCOME_TAG = "r3x.job_outcome".freeze
    FORMAT_MUTEX = Mutex.new

    def self.tag(name, value)
      return if value.blank?

      "#{name}=#{value}"
    end

    def self.format
      FORMAT_MUTEX.synchronize do
        @format ||= begin
          require_relative "env" unless defined?(R3x::Env)

          format = R3x::Env.fetch("R3X_LOG_FORMAT")
          case format
          when nil, "plain"
            "plain"
          when "json"
            "json"
          else
            raise ArgumentError, "Unsupported R3X_LOG_FORMAT: #{format.inspect}. Use 'json' or 'plain'."
          end
        end
      end
    end

    def self.json?
      format == "json"
    end

    def self.plain?
      !json?
    end
  end
end

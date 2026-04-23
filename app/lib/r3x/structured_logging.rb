module R3x
  module StructuredLogging
    def structured_error(message:, error:)
      return unless json_logging_enabled?

      payload = {
        level: "error",
        time: Time.current.utc.iso8601(6),
        message: message,
        error_class: error.class.name,
        error_message: error.message,
        backtrace: error.backtrace&.first(20),
        tags: current_log_tags
      }
      formatted = R3x::LogFormatter.new.call("error", Time.current, nil, payload)
      Rails.logger << formatted
    end

    private

    def current_log_tags
      formatter = Rails.logger.formatter
      return [] unless formatter.respond_to?(:tag_stack)

      formatter.tag_stack.tags
    end

    def json_logging_enabled?
      Rails.logger.formatter.is_a?(R3x::LogFormatter)
    end
  end
end

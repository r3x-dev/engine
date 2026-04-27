module R3x
  module StructuredLogging
    def structured_error(message:, error:)
      if R3x::Log.json?
        payload = {
          level: "error",
          time: Time.current.utc.iso8601(6),
          message: message,
          error_class: error.class.name,
          error_message: error.message,
          backtrace: error.backtrace&.first(20),
          tags: current_log_tags
        }
        formatted = R3x::Log::JsonFormatter.new.call("error", Time.current, nil, payload)
        Rails.logger << formatted
      else
        logger.error "#{message} error_class=#{error.class} error_message=#{error.message}"
      end
    end

    private

    def current_log_tags
      formatter = Rails.logger.formatter
      return [] unless formatter.respond_to?(:tag_stack)

      formatter.tag_stack.tags
    end
  end
end

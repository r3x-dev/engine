# frozen_string_literal: true

module R3x
  module StructuredLogging
    def structured_error(message:, error:)
      details = R3x::ErrorDetails.new(error)

      if R3x::Log.json?
        payload = {
          level: "error",
          time: Time.current.utc.iso8601(6),
          message:,
          error_class: details.error_class,
          error_message: details.message,
          backtrace: details.backtrace&.first(20),
          tags: current_log_tags,
        }
        formatted = R3x::Log::JsonFormatter.new.call("error", Time.current, nil, payload)
        Rails.logger << formatted
      else
        logger.error "#{message} error_class=#{details.error_class} error_message=#{details.message}"
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

module R3x
  class ConfigurationError < ArgumentError
    attr_reader :subject, :errors, :message_prefix

    def initialize(message = nil, subject: nil, errors: nil, message_prefix: nil)
      @subject = subject
      @errors = errors
      @message_prefix = message_prefix

      super(message || default_message)
    end

    private

    def default_message
      parts = []
      parts << subject_label if subject_label
      parts << message_prefix if message_prefix
      parts << errors&.full_messages&.to_sentence if errors
      parts.compact.join(": ")
    end

    def subject_label
      return nil unless subject

      if subject.respond_to?(:validation_subject)
        subject.validation_subject
      else
        subject.class.name
      end
    end
  end
end

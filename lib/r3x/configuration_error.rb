module R3x
  class ConfigurationError < ArgumentError
    attr_reader :subject, :errors

    def initialize(message = nil, subject: nil, errors: nil)
      @subject = subject
      @errors = errors

      super(message || default_message)
    end

    private

    def default_message
      [ subject_label, errors&.full_messages&.to_sentence ].compact.join(": ")
    end

    def subject_label
      return "Invalid configuration" unless subject

      if subject.respond_to?(:validation_subject)
        subject.validation_subject
      else
        subject.class.name
      end
    end
  end
end

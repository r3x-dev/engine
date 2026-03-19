module R3x
  module Dsl
    module Validatable
      extend ActiveSupport::Concern

      included do
        include ActiveModel::Validations

        define_method(:validate!) do |message_prefix: nil|
          return true if valid?

          message = [ message_prefix, errors.full_messages.to_sentence ].compact.join(": ")
          raise ConfigurationError.new(message, subject: self, errors: errors)
        end
      end

      def validation_subject
        self.class.name
      end
    end
  end
end

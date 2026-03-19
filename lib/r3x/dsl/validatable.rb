module R3x
  module Dsl
    module Validatable
      extend ActiveSupport::Concern

      included do
        include ActiveModel::Validations

      define_method(:validate!) do |message_prefix: nil|
        return true if valid?

        raise ConfigurationError.new(nil, subject: self, errors: errors, message_prefix: message_prefix)
      end
      end

      def validation_subject
        self.class.name
      end
    end
  end
end

# frozen_string_literal: true

module R3x
  module Validators
    class TriggerKey < ActiveModel::Validator
      def validate(record)
        key = record.key
        return if key.nil?
        return if key.is_a?(String) && /\A[a-z][a-z0-9_]*\z/.match?(key)

        record.errors.add(:key, "must be a lowercase name starting with a letter and containing only letters, digits and underscores")
      end
    end
  end
end

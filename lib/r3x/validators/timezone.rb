module R3x
  module Validators
    class Timezone < ActiveModel::Validator
      def initialize(options = {})
        super
        @timezone_field = options[:timezone_field] || :timezone
        @allow_blank = options[:allow_blank]
      end

      def validate(record)
        value = record.public_send(@timezone_field)
        return if @allow_blank && (value.nil? || value.empty?)

        self.class.validate!(value, field_name: @timezone_field.to_s)
      rescue ArgumentError => e
        record.errors.add(@timezone_field, e.message)
      end

      def self.validate!(value, field_name: "timezone")
        return if value.nil? || value.empty?

        normalize(value, field_name:)
      end

      def self.normalize(value, field_name: "timezone")
        timezone = resolve(value)
        return timezone if timezone

        raise ArgumentError, "#{field_name}: '#{value}' is not a valid timezone"
      end

      def self.resolve(value)
        timezone_name = value.to_s.strip
        return if timezone_name.empty?

        timezone_identifier = ActiveSupport::TimeZone[timezone_name]&.tzinfo&.identifier || direct_timezone(timezone_name)&.identifier
        canonicalize_identifier(timezone_identifier)
      end

      def self.canonicalize_identifier(identifier)
        return if identifier.blank?

        %w[UTC Etc/UTC].include?(identifier) ? "UTC" : identifier
      end

      def self.direct_timezone(timezone_name)
        TZInfo::Timezone.get(timezone_name)
      rescue TZInfo::InvalidTimezoneIdentifier
        nil
      end
    end
  end
end

module R3x
  module Validators
    class Timezone < ActiveModel::Validator
      def initialize(options = {})
        super
        @timezone_field = options[:timezone_field] || :timezone
      end

      def validate(record)
        value = record.public_send(@timezone_field)

        self.class.validate!(value, field_name: @timezone_field.to_s)
      rescue ArgumentError => e
        record.errors.add(@timezone_field, e.message)
      end

      def self.validate!(value, field_name: "timezone")
        return if value.blank?

        normalize(value, field_name:)
      end

      def self.normalize(value, field_name: "timezone")
        timezone = resolve(value)
        return timezone if timezone

        raise ArgumentError, "#{field_name}: '#{value}' is not a valid timezone"
      end

      def self.resolve(value)
        timezone_name = timezone_name_for(value)

        return if timezone_name.blank?

        timezone_identifier = ActiveSupport::TimeZone[timezone_name]&.tzinfo&.identifier || direct_timezone(timezone_name)&.identifier
        canonicalize_identifier(timezone_identifier)
      end

      def self.timezone_name_for(value)
        if value.respond_to?(:tzinfo) && value.tzinfo.respond_to?(:identifier)
          value.tzinfo.identifier
        elsif value.respond_to?(:identifier)
          value.identifier
        else
          value.to_s.strip
        end
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

module R3x
  module Validators
    class Url < ActiveModel::Validator
      def initialize(options = {})
        super
        @url_field = options[:url_field] || :url
        @allow_blank = options[:allow_blank]
      end

      def validate(record)
        value = record.public_send(@url_field)
        if value.nil? || value.empty?
          record.errors.add(@url_field, "can't be blank") unless @allow_blank
          return
        end

        self.class.validate!(value, field_name: @url_field.to_s)
      rescue ArgumentError => e
        record.errors.add(@url_field, e.message)
      end

      def self.validate!(value, field_name: "url")
        return if value.nil? || value.empty?

        uri = URI.parse(value)
        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          raise ArgumentError, "#{field_name}: '#{value}' is not a valid HTTP/HTTPS URL"
        end
      rescue URI::InvalidURIError
        raise ArgumentError, "#{field_name}: '#{value}' is not a valid HTTP/HTTPS URL"
      end
    end
  end
end

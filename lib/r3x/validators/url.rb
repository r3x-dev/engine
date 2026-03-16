module R3x
  module Validators
    class Url
      def self.validate!(value, field_name: "url")
        return if value.nil? || value.empty?

        uri = URI.parse(value)
        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          raise ArgumentError, "#{field_name}: '#{value}' is not a valid HTTP/HTTPS URL"
        end
      rescue URI::InvalidURIError => e
        raise ArgumentError, "#{field_name}: '#{value}' is not a valid URL (#{e.message})"
      end
    end
  end
end

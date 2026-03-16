require "fugit"

module R3x
  module Validators
    class Cron
      def self.validate!(value, field_name: "cron")
        return if value.nil? || value.empty?

        parsed = Fugit.parse(value, multi: :fail)
        unless parsed.is_a?(Fugit::Cron)
          raise ArgumentError, "#{field_name}: '#{value}' is not a valid cron expression"
        end
      rescue ArgumentError => e
        raise ArgumentError, "#{field_name}: '#{value}' is not a valid cron expression (#{e.message})"
      end
    end
  end
end

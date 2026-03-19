require "fugit"

module R3x
  module Validators
    class Cron < ActiveModel::Validator
      def initialize(options = {})
        super
        @cron_field = options[:cron_field] || :cron
        @allow_blank = options[:allow_blank]
      end

      def validate(record)
        value = record.public_send(@cron_field)
        return if @allow_blank && (value.nil? || value.empty?)

        parsed = Fugit.parse(value, multi: :fail)
        unless parsed.is_a?(Fugit::Cron)
          record.errors.add(@cron_field, "is not a valid cron expression")
        end
      rescue ArgumentError
        record.errors.add(@cron_field, "is not a valid cron expression")
      end

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

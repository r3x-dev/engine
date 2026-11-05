# frozen_string_literal: true

module R3x
  module Client
    class Delivery < Data.define(:status, :message)
      def initialize(status:, message: nil)
        case status
        when :delivered
          raise ArgumentError, "Delivered result requires a message" if message.nil?
        when :dry_run
          raise ArgumentError, "Dry-run delivery cannot have a message" unless message.nil?
        else
          raise ArgumentError, "Unsupported delivery status: #{status.inspect}"
        end

        super(status:, message:)
      end

      def delivered?
        status == :delivered
      end

      def dry_run?
        status == :dry_run
      end
    end
  end
end

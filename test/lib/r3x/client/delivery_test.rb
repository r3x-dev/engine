# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class DeliveryTest < ActiveSupport::TestCase
      test "delivered result retains the original message" do
        message = { "id" => "message-123", "content" => "Hello" }

        delivery = Delivery.new(status: :delivered, message:)

        assert_predicate delivery, :delivered?
        assert_not_predicate delivery, :dry_run?
        assert_equal :delivered, delivery.status
        assert_same message, delivery.message
        assert_predicate delivery, :frozen?
      end

      test "dry run delivery has no message" do
        delivery = Delivery.new(status: :dry_run)

        assert_predicate delivery, :dry_run?
        assert_not_predicate delivery, :delivered?
        assert_nil delivery.message
      end

      test "rejects unsupported statuses" do
        [nil, "delivered", :failed].each do |status|
          assert_raises(ArgumentError) { Delivery.new(status:) }
        end
      end

      test "delivered result requires a message" do
        assert_raises(ArgumentError) { Delivery.new(status: :delivered) }
      end

      test "dry run delivery rejects a message" do
        assert_raises(ArgumentError) { Delivery.new(status: :dry_run, message: { "id" => "message-123" }) }
      end
    end
  end
end

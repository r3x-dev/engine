require "test_helper"

module R3x
  module Validators
    class TimezoneTest < ActiveSupport::TestCase
      class DummyModel
        include ActiveModel::Validations

        attr_reader :timezone

        validates_with R3x::Validators::Timezone, timezone_field: :timezone, allow_blank: true

        def initialize(timezone:)
          @timezone = timezone
        end
      end

      test "accepts IANA timezone names" do
        assert_nothing_raised do
          R3x::Validators::Timezone.validate!("Europe/Paris")
        end
      end

      test "accepts Rails timezone names" do
        assert_nothing_raised do
          R3x::Validators::Timezone.validate!("Pacific Time (US & Canada)")
        end
      end

      test "rejects invalid timezone" do
        error = assert_raises(ArgumentError) do
          R3x::Validators::Timezone.validate!("Mars/Olympus")
        end

        assert_equal "timezone: 'Mars/Olympus' is not a valid timezone", error.message
      end

      test "normalize returns TZInfo name for Rails timezone" do
        assert_equal "America/Los_Angeles", R3x::Validators::Timezone.normalize("Pacific Time (US & Canada)")
      end

      test "normalize returns TZInfo name for IANA timezone" do
        assert_equal "Europe/Paris", R3x::Validators::Timezone.normalize("Europe/Paris")
      end

      test "normalize canonicalizes UTC aliases" do
        assert_equal "UTC", R3x::Validators::Timezone.normalize("UTC")
        assert_equal "UTC", R3x::Validators::Timezone.normalize("Etc/UTC")
      end

      test "allows blank when allow_blank is set" do
        assert DummyModel.new(timezone: "").valid?
        assert DummyModel.new(timezone: nil).valid?
      end

      test "ActiveModel form rejects invalid timezone" do
        model = DummyModel.new(timezone: "Mars/Olympus")

        assert_not model.valid?
        assert_includes model.errors[:timezone], "timezone: 'Mars/Olympus' is not a valid timezone"
      end
    end
  end
end

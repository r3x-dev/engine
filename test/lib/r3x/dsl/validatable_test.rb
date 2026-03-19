require "test_helper"

module R3x
  module Dsl
    class ValidatableTest < ActiveSupport::TestCase
      class DummyObject
        include Validatable

        attr_reader :name, :cron

        validates :name, presence: true
        validates :cron, presence: true

        def initialize(name:, cron:)
          @name = name
          @cron = cron
        end

        def validation_subject
          "dummy DSL object"
        end
      end

      test "validate! raises a single configuration error with all validation messages" do
        object = DummyObject.new(name: "", cron: nil)

        error = assert_raises(ConfigurationError) do
          object.validate!
        end

        assert_equal object, error.subject
        assert_equal object.errors, error.errors
        assert_includes error.message, "Name can't be blank"
        assert_includes error.message, "Cron can't be blank"
      end
    end
  end
end

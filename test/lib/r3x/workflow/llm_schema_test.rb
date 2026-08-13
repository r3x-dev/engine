# frozen_string_literal: true

require "test_helper"

module R3x
  module Workflow
    class LlmSchemaTest < ActiveSupport::TestCase
      test "define loads Schematist lazily and returns a schema class" do
        klass = LlmSchema.define do
          string :status
        end

        assert_operator klass, :<, Schematist::Schema
        assert_equal [:status], klass.properties.keys
      end
    end
  end
end

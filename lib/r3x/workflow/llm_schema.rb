# frozen_string_literal: true

module R3x
  module Workflow
    module LlmSchema
      extend self

      def define(&)
        R3x::GemLoader.require("schematist")

        Class.new(Schematist::Schema, &)
      end
    end
  end
end

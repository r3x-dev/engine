# frozen_string_literal: true

module RuboCop
  module Cop
    module R3x
      # This cop flags direct reads of R3X_* environment variables.
      # Application code should use R3x::Env helpers, which treat blank env
      # values as missing and provide strict boolean parsing.
      #
      # @example
      #   # bad
      #   ENV["R3X_FOO"]
      #   ENV.fetch("R3X_FOO")
      #   ENV.fetch("R3X_FOO", "default")
      #   ENV.key?("R3X_FOO")
      #   ENV.present?("R3X_FOO")
      #
      #   # good
      #   R3x::Env.fetch("R3X_FOO")
      #   R3x::Env.fetch!("R3X_FOO")
      #   R3x::Env.fetch_boolean("R3X_FOO")
      #   R3x::Env.present?("R3X_FOO")
      #
      class PreferR3xEnv < Base
        MSG = "Use R3x::Env.fetch / fetch! / fetch_boolean / present? for R3X_* environment variables."

        def_node_matcher :direct_r3x_env_read?, <<~PATTERN
          (send (const {nil? cbase} :ENV) {:[] :fetch :key? :present?} (str #r3x_env_key?) ...)
        PATTERN

        def on_send(node)
          return unless direct_r3x_env_read?(node)

          add_offense(node)
        end

        private

        def r3x_env_key?(value)
          value.start_with?("R3X_")
        end
      end
    end
  end
end

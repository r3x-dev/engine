# frozen_string_literal: true

module RuboCop
  module Cop
    module R3x
      # This cop flags direct reads of R3X_* environment variables.
      # Application code should use R3x::Env helpers, which treat blank env
      # values as missing and provide strict boolean parsing.
      # Integration clients use these helpers for every provider or dynamic key too.
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
        MSG = "Use R3x::Env.fetch / fetch! / secure_fetch / fetch_boolean / present? instead of reading ENV directly."
        RESTRICT_ON_SEND = %i[[] fetch key? present?].freeze

        def_node_matcher :direct_env_read, <<~PATTERN
          (send (const {nil? cbase} :ENV) {:[] :fetch :key? :present?} $_ ...)
        PATTERN

        def on_send(node)
          key = direct_env_read(node)
          return unless key
          return unless integration_client? || (key.str_type? && r3x_env_key?(key.value))

          add_offense(node)
        end

        private

        def integration_client?
          config.path_relative_to_config(processed_source.file_path).start_with?("app/lib/r3x/client/")
        end

        def r3x_env_key?(value)
          value.start_with?("R3X_")
        end
      end
    end
  end
end

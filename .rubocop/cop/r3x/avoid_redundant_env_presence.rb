# frozen_string_literal: true

module RuboCop
  module Cop
    module R3x
      # This cop flags redundant `.presence` calls on `R3x::Env.fetch`, `R3x::Env.fetch!`,
      # and `R3x::Env.secure_fetch`.
      # Since `R3x::Env` fetchers already apply `.presence` to the read environment variable
      # internally, appending `.presence` is redundant and can be omitted.
      #
      # @example
      #   # bad
      #   R3x::Env.fetch("R3X_LOGS_PROVIDER").presence
      #   R3x::Env.fetch!("R3X_LOGS_PROVIDER").presence
      #   R3x::Env.secure_fetch("API_KEY", prefix: "PROV_").presence
      #
      #   # good
      #   R3x::Env.fetch("R3X_LOGS_PROVIDER")
      #   R3x::Env.fetch!("R3X_LOGS_PROVIDER")
      #   R3x::Env.secure_fetch("API_KEY", prefix: "PROV_")
      #
      class AvoidRedundantEnvPresence < Base
        extend AutoCorrector

        MSG = "Avoid redundant `.presence` call on `R3x::Env` fetchers."

        def_node_matcher :redundant_presence?, <<~PATTERN
          (send $(send (const (const {nil? cbase} :R3x) :Env) {:fetch :fetch! :secure_fetch} ...) :presence)
        PATTERN

        def on_send(node)
          redundant_presence?(node) do |inner_node|
            add_offense(node) do |corrector|
              corrector.replace(node, inner_node.source)
            end
          end
        end
      end
    end
  end
end

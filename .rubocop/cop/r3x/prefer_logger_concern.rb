# frozen_string_literal: true

module RuboCop
  module Cop
    module R3x
      # This cop flags direct usage of `Rails.logger` in integration clients
      # and other classes under `app/lib/r3x/client/`. Those files should
      # instead use the `logger` method provided by `R3x::Concerns::Logger`.
      #
      # @example
      #   # bad
      #   Rails.logger.info("something")
      #
      #   # good
      #   include R3x::Concerns::Logger
      #   logger.info("something")
      #
      class PreferLoggerConcern < Base
        MSG = "Use the logger concern (`include R3x::Concerns::Logger`) and call `logger` instead of `Rails.logger` directly."

        def_node_matcher :rails_logger?, <<~PATTERN
          (send (const {nil? cbase} :Rails) :logger)
        PATTERN

        def on_send(node)
          return unless rails_logger?(node)

          add_offense(node)
        end
      end
    end
  end
end

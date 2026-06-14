# frozen_string_literal: true

module RuboCop
  module Cop
    module R3x
      # This cop flags the use of `Hash#tap` on hash literals for simple conditional key additions.
      #
      # @example
      #   # bad
      #   {
      #     timeout: timeout
      #   }.tap do |opts|
      #     opts[:ssl] = true if verify_ssl
      #   end
      #
      #   # good
      #   opts = { timeout: timeout }
      #   opts[:ssl] = true if verify_ssl
      #   opts
      #
      class AvoidHashTap < Base
        MSG = "Avoid tap nesting for simple conditional key additions. Build the base hash first, conditionally assign the optional keys, and return the hash."

        def_node_matcher :hash_tap?, <<~PATTERN
          (block (send hash :tap) ...)
        PATTERN

        def on_block(node)
          return unless hash_tap?(node)

          add_offense(node)
        end
      end
    end
  end
end

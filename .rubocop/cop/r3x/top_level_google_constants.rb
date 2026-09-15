# frozen_string_literal: true

module RuboCop
  module Cop
    module R3x
      # This cop flags unqualified references to third-party Google namespaces.
      # Client code lives below R3x::Client::Google, so an unqualified Google
      # reference can resolve to the project's namespace instead of the SDK.
      #
      # @example
      #   # bad
      #   Google::Apis::SheetsV4::SheetsService.new
      #
      #   # good
      #   ::Google::Apis::SheetsV4::SheetsService.new
      #   Google::Gmail::Thing.new
      #   R3x::Client::Google::Gmail.new
      #   module Google
      #   end
      #
      class TopLevelGoogleConstants < Base
        extend AutoCorrector

        GOOGLE_SDK_NAMESPACES = %w[Apis Auth Cloud].freeze
        MSG = "Reference third-party Google constants with a leading `::` (for example, `::Google::Apis::...`)."

        def on_const(node)
          return unless unqualified_google_sdk_reference?(node)

          add_offense(node) do |corrector|
            corrector.insert_before(node, "::")
          end
        end

        private

        def unqualified_google_sdk_reference?(node)
          return false if constant_definition?(node)

          namespace, name = *node
          GOOGLE_SDK_NAMESPACES.include?(name.to_s) && namespace&.const_type? && namespace.children == [nil, :Google]
        end

        def constant_definition?(node)
          node = node.parent while node.parent&.const_type?
          parent = node.parent
          return false unless parent
          return false unless parent.class_type? || parent.module_type?

          parent.identifier == node
        end
      end
    end
  end
end

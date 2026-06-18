# frozen_string_literal: true

module RuboCop
  module Cop
    module R3x
      # Flags manual global method patching in tests.
      #
      # @example
      #   # bad
      #   HighLine.define_singleton_method(:new) { fake }
      #
      #   # bad
      #   Signet::OAuth2::Client.singleton_class.define_method(:new) { fake }
      #
      #   # good
      #   HighLine.stubs(:new).returns(fake)
      #
      #   # good
      #   Class.new { def choose = :all }
      #
      class NoManualMethodPatchingInTests < Base
        MSG = "Use Mocha stubs/expects or a plain fake class instead of manually patching methods in tests."
        RESTRICT_ON_SEND = %i[define_singleton_method define_method alias_method remove_method].freeze

        def on_send(node)
          case node.method_name
          when :define_singleton_method
            add_offense(node) if constant_receiver?(node.receiver)
          when :define_method, :alias_method, :remove_method
            add_offense(node) if singleton_class_receiver?(node.receiver)
          end
        end

        private

        def constant_receiver?(receiver)
          receiver&.const_type?
        end

        def singleton_class_receiver?(receiver)
          receiver&.send_type? && receiver.method?(:singleton_class)
        end
      end
    end
  end
end

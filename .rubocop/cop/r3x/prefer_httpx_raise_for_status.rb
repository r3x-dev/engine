# frozen_string_literal: true

module RuboCop
  module Cop
    module R3x
      # This cop flags manual 2xx checks on HTTPX responses.
      #
      # @example
      #   # bad
      #   response.status >= 200 && response.status < 300
      #
      #   # good
      #   response.raise_for_status
      #
      class PreferHttpxRaiseForStatus < Base
        MSG = "Use `%<response>s.raise_for_status` instead of hand-rolling a 2xx status check."

        def_node_matcher :manual_success_check?, <<~PATTERN
          (and
            (send (send $_ :status) :>= (int 200))
            (send (send $_ :status) :< (int 300)))
        PATTERN

        def on_and(node)
          manual_success_check?(node) do |left_response, right_response|
            next unless same_response?(left_response, right_response)
            next unless response_node?(left_response)

            add_offense(node, message: format(MSG, response: left_response.source))
          end
        end

        private

        def same_response?(left_response, right_response)
          return false unless left_response && right_response

          left_response.source == right_response.source
        end

        def response_node?(node)
          if node.lvar_type? || node.ivar_type? || node.send_type?
            name = case node.type
            when :lvar, :ivar then node.name.to_s
            when :send then node.method_name.to_s
            end
            return true if name.match?(/\A@?(response|res|resp|http_response)\z/i)
          end

          httpx_call?(node)
        end

        def httpx_call?(node)
          return false unless node.send_type?

          receiver = node.receiver
          return false unless receiver

          if receiver.const_type? && receiver.short_name == :HTTPX
            true
          else
            httpx_call?(receiver)
          end
        end
      end
    end
  end
end

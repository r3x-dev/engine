# frozen_string_literal: true

module RuboCop
  module Cop
    module R3x
      # This cop flags direct calls to `MultiJSON.parse` or `MultiJSON.load` on HTTPX response bodies.
      # Code should use `response.json` (or `res.json`, etc.) instead.
      #
      # @example
      #   # bad
      #   MultiJSON.parse(response.body)
      #   MultiJSON.parse(response.body.to_s)
      #   MultiJSON.load(res.body)
      #
      #   # good
      #   response.json
      #   res.json
      #
      class PreferHttpxResponseJson < Base
        extend AutoCorrector

        MSG = "Use `%<response>s.json` instead of passing the response body to `MultiJSON.parse`."

        def_node_matcher :multijson_parse_on_body?, <<~PATTERN
          (send
            (const {nil? cbase} :MultiJSON)
            {:parse | :load}
            {
              (send $_ :body)
              (send (send $_ :body) :to_s)
            }
            ...
          )
        PATTERN

        def on_send(node)
          multijson_parse_on_body?(node) do |response_node|
            next unless response_node?(response_node)

            add_offense(node, message: format(MSG, response: response_node.source)) do |corrector|
              corrector.replace(node, "#{response_node.source}.json")
            end
          end
        end

        private

        def response_node?(node)
          # 1. Local variables, instance variables, or method calls named response, res, resp, http_response
          if node.lvar_type? || node.ivar_type? || node.send_type?
            name = case node.type
            when :lvar, :ivar then node.name.to_s
            when :send then node.method_name.to_s
            end
            return true if name.match?(/\A@?(response|res|resp|http_response)\z/i)
          end

          # 2. Check if it's a direct chain starting with HTTPX constant
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

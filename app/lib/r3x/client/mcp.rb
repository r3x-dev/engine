# frozen_string_literal: true

module R3x
  module Client
    class Mcp
      JSON_RPC_VERSION = "2.0"
      PROTOCOL_VERSION = "2025-11-25"

      def initialize(url:, headers: {}, timeout: 30)
        @url = url
        @connection = HTTPX.with(
          headers: headers.merge(
            "Accept"               => "application/json, text/event-stream",
            "MCP-Protocol-Version" => PROTOCOL_VERSION,
          ),
          timeout: { total_request_timeout: timeout },
        )
      end

      def call_tool(name, arguments: {})
        raise ArgumentError, "name must be a nonblank string" unless name.is_a?(String) && name.present?
        raise ArgumentError, "arguments must be an object" unless arguments.is_a?(Hash)

        initialize_protocol
        result = rpc("tools/call", name:, arguments:)
        raise "MCP tool failed: #{name}" if result["isError"]

        result
      end

      private

      attr_reader :url, :connection

      def initialize_protocol
        result = rpc("initialize", protocolVersion: PROTOCOL_VERSION, capabilities: {}, clientInfo: { name: "r3x", version: "1" })
        unless result["protocolVersion"] == PROTOCOL_VERSION
          raise R3x::ConfigurationError, "Unsupported MCP protocol version"
        end

        connection.post(url, json: { jsonrpc: JSON_RPC_VERSION, method: "notifications/initialized" }).raise_for_status
      end

      def rpc(method, **params)
        response = connection.post(url, json: { jsonrpc: JSON_RPC_VERSION, id: 1, method:, params: }).raise_for_status.json
        unless response.is_a?(Hash) && response["jsonrpc"] == JSON_RPC_VERSION && response["id"] == 1
          raise "Invalid MCP response"
        end
        raise "MCP request failed: #{method}" if response.key?("error")

        result = response["result"]
        raise "MCP result must be an object" unless result.is_a?(Hash)

        result
      end
    end
  end
end

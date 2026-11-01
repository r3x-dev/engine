# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class McpTest < ActiveSupport::TestCase
      test "calls an arbitrary tool over HTTP and preserves the complete MCP result" do
        arguments = { url: "https://example.test/document", options: { language: "pt" } }
        result = {
          "structuredContent" => { "title" => "A document", "text" => "Content" },
          "content"           => [{ "type" => "text", "text" => "A document" }],
          "isError"           => false,
          "_meta"             => { "revision" => 2 },
        }
        stub_protocol
        stub_mcp("tools/call", params: { name: "inspect_document", arguments: }, result:)

        assert_equal result, client.call_tool("inspect_document", arguments:)
      end

      test "accepts a text-only result and defaults to empty arguments" do
        result = { "content" => [{ "type" => "text", "text" => "Available" }] }
        stub_protocol
        stub_mcp("tools/call", params: { name: "source_status", arguments: {} }, result:)

        assert_equal result, client.call_tool("source_status")
      end

      test "preserves a successful empty list result" do
        result = { "structuredContent" => { "items" => [] } }
        stub_protocol
        stub_mcp("tools/call", params: { name: "list_documents", arguments: {} }, result:)

        assert_equal result, client.call_tool("list_documents")
      end

      test "does not treat an MCP tool error in HTTP 200 as an empty result" do
        stub_protocol
        stub_mcp("tools/call", params: { name: "inspect_document", arguments: {} }, result: { "isError" => true, "content" => [{ "type" => "text", "text" => "upstream failed" }] })

        error = assert_raises(RuntimeError) { client.call_tool("inspect_document") }

        assert_match "MCP tool failed: inspect_document", error.message
      end

      test "rejects an incompatible protocol before calling the tool" do
        stub_mcp("initialize", result: { "protocolVersion" => "unsupported" })

        assert_raises(R3x::ConfigurationError) { client.call_tool("inspect_document") }

        assert_not_requested(:post, "http://mcp.test/rpc", body: hash_including(method: "tools/call"))
      end

      test "rejects invalid tool names before any request" do
        [nil, "", " ", :inspect_document].each do |name|
          assert_raises(ArgumentError) { client.call_tool(name) }
        end

        assert_not_requested :post, "http://mcp.test/rpc"
      end

      test "rejects non-object arguments before any request" do
        assert_raises(ArgumentError) { client.call_tool("inspect_document", arguments: []) }

        assert_not_requested :post, "http://mcp.test/rpc"
      end

      test "supports a server without authentication headers" do
        stub_request(:post, "http://public-mcp.test/rpc")
          .with(body: hash_including(method: "initialize"))
          .to_return_json(body: { jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-11-25" } })
        stub_request(:post, "http://public-mcp.test/rpc")
          .with(body: { jsonrpc: "2.0", method: "notifications/initialized" })
          .to_return(status: 202)
        request = stub_request(:post, "http://public-mcp.test/rpc")
          .with(body: hash_including(method: "tools/call")) { |request| !request.headers.key?("Authorization") }
          .to_return_json(body: { jsonrpc: "2.0", id: 1, result: { content: [] } })

        result = Mcp.new(url: "http://public-mcp.test/rpc").call_tool("source_status")

        assert_equal({ "content" => [] }, result)
        assert_requested request
      end

      test "rejects a JSON-RPC error returned with HTTP 200" do
        stub_protocol
        stub_request(:post, "http://mcp.test/rpc")
          .with(body: hash_including(method: "tools/call"))
          .to_return_json(body: { jsonrpc: "2.0", id: 1, error: { code: -32602, message: "Invalid arguments" } })

        error = assert_raises(RuntimeError) { client.call_tool("inspect_document") }

        assert_match "MCP request failed: tools/call", error.message
      end

      test "rejects malformed or mismatched JSON-RPC responses" do
        stub_protocol
        [[], { jsonrpc: "1.0", id: 1, result: {} }, { jsonrpc: "2.0", id: 2, result: {} }].each do |response|
          stub_request(:post, "http://mcp.test/rpc")
            .with(body: hash_including(method: "tools/call"))
            .to_return_json(body: response)

          error = assert_raises(RuntimeError) { client.call_tool("inspect_document") }

          assert_match "Invalid MCP response", error.message
        end
      end

      test "rejects a missing or non-object result" do
        stub_protocol
        [nil, []].each do |result|
          stub_mcp("tools/call", params: { name: "inspect_document", arguments: {} }, result:)

          error = assert_raises(RuntimeError) { client.call_tool("inspect_document") }

          assert_match "MCP result must be an object", error.message
        end
      end

      private

      def stub_protocol
        stub_mcp("initialize", result: { "protocolVersion" => "2025-11-25" })
        stub_request(:post, "http://mcp.test/rpc")
          .with(body: { jsonrpc: "2.0", method: "notifications/initialized" })
          .to_return(status: 202)
      end

      def stub_mcp(method, result:, params: nil)
        payload = { jsonrpc: "2.0", id: 1, method: }
        payload[:params] = params if params
        matcher = params ? payload : hash_including(payload)
        stub_request(:post, "http://mcp.test/rpc")
          .with(body: matcher, headers: { "Authorization" => "Bearer test-token", "Accept" => "application/json, text/event-stream" })
          .to_return(status: 200, body: MultiJSON.generate({ jsonrpc: "2.0", id: 1, result: }), headers: { "Content-Type" => "application/json" })
      end

      def client
        Mcp.new(url: "http://mcp.test/rpc", headers: { "Authorization" => "Bearer test-token" })
      end
    end
  end
end

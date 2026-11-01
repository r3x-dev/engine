# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class SourcetapTest < ActiveSupport::TestCase
      test "configures MCP from the default Sourcetap environment and preserves its result" do
        result = { "structuredContent" => { "title" => "A document" }, "_meta" => { "revision" => 2 } }
        stub_tool("https://sourcetap.test/mcp", token: "test-token", result:)

        with_client_env("SOURCETAP_URL" => "https://sourcetap.test/mcp", "SOURCETAP_AUTH_TOKEN" => "test-token") do
          assert_equal result, R3x::Workflow::Context::Client.sourcetap.call_tool("inspect_document", arguments: { language: "pt" })
        end
      end

      test "uses the explicitly selected endpoint and credential variants" do
        result = { "content" => [{ "type" => "text", "text" => "A document" }] }
        stub_tool("http://archive.test/mcp", token: "archive-token", result:)

        with_client_env("SOURCETAP_URL_ARCHIVE" => "http://archive.test/mcp", "SOURCETAP_AUTH_TOKEN_ARCHIVE" => "archive-token") do
          client = R3x::Workflow::Context::Client.sourcetap(url_env: "SOURCETAP_URL_ARCHIVE", auth_token_env: "SOURCETAP_AUTH_TOKEN_ARCHIVE")

          assert_equal result, client.call_tool("inspect_document", arguments: { language: "pt" })
        end
      end

      private

      def stub_tool(url, token:, result:)
        headers = { "Authorization" => "Bearer #{token}", "Accept" => "application/json, text/event-stream" }
        stub_request(:post, url)
          .with(body: hash_including(method: "initialize"), headers:)
          .to_return_json(body: { jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-11-25" } })
        stub_request(:post, url)
          .with(body: { jsonrpc: "2.0", method: "notifications/initialized" }, headers:)
          .to_return(status: 202)
        stub_request(:post, url)
          .with(body: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "inspect_document", arguments: { language: "pt" } } }, headers:)
          .to_return_json(body: { jsonrpc: "2.0", id: 1, result: })
      end

      def with_client_env(keys)
        originals = keys.to_h { |key, _| [key, ENV[key]] }
        keys.each { |key, value| ENV[key] = value }
        yield
      ensure
        originals.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      end
    end
  end
end

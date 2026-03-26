require "test_helper"

module R3x
  module Client
    class HashiCorpVaultTest < ActiveSupport::TestCase
      setup do
        @original_vault_addr = ENV["R3X_VAULT_ADDR"]
        @original_vault_token = ENV["R3X_VAULT_TOKEN"]
        reset_vault_singleton
      end

      teardown do
        ENV["R3X_VAULT_ADDR"] = @original_vault_addr
        ENV["R3X_VAULT_TOKEN"] = @original_vault_token
        WebMock.reset!
        reset_vault_singleton
      end

      test "reads kv v2 data from vault" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/v1/secret/data/env/r3x")
          .with(headers: { "X-Vault-Token" => "test-token" })
          .to_return(
            status: 200,
            body: {
              data: {
                data: {
                  api_key: "test-api-key"
                },
                metadata: { version: 1 }
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        result = HashiCorpVault.read("secret/data/env/r3x")

        assert_equal({
          "api_key" => "test-api-key"
        }, result)
      end

      test "raises when required vault config is missing" do
        ENV["R3X_VAULT_ADDR"] = nil
        ENV["R3X_VAULT_TOKEN"] = nil
        reset_vault_singleton

        error = assert_raises(ArgumentError) do
          HashiCorpVault.read("secret/data/env/r3x")
        end

        assert_equal "Missing R3X_VAULT_ADDR", error.message
      end

      test "raises when vault config is blank string" do
        ENV["R3X_VAULT_ADDR"] = ""
        ENV["R3X_VAULT_TOKEN"] = ""
        reset_vault_singleton

        error = assert_raises(ArgumentError) do
          HashiCorpVault.read("secret/data/env/r3x")
        end

        assert_equal "Missing R3X_VAULT_ADDR", error.message
      end

      test "raises when vault returns a non-success status" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/v1/secret/data/env/r3x")
          .with(headers: { "X-Vault-Token" => "test-token" })
          .to_return(
            status: 403,
            body: { errors: [ "permission denied" ] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        error = assert_raises(RuntimeError) do
          HashiCorpVault.read("secret/data/env/r3x")
        end

        assert_equal 'Vault request failed with status 403: ["permission denied"]', error.message
      end

      test "raises when kv v2 payload is missing" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/v1/secret/data/env/r3x")
          .with(headers: { "X-Vault-Token" => "test-token" })
          .to_return(
            status: 200,
            body: { data: { metadata: { version: 1 } } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        error = assert_raises(RuntimeError) do
          HashiCorpVault.read("secret/data/env/r3x")
        end

        assert_equal "Vault response missing KV v2 data at data.data", error.message
      end

      test "raises when vault returns non-hash data payload" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/v1/secret/data/env/r3x")
          .with(headers: { "X-Vault-Token" => "test-token" })
          .to_return(
            status: 200,
            body: { data: { data: "not-a-hash" } }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        error = assert_raises(RuntimeError) do
          HashiCorpVault.read("secret/data/env/r3x")
        end

        assert_equal "Vault response missing KV v2 data at data.data", error.message
      end

      test "raises when vault returns non-object body" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/v1/secret/data/env/r3x")
          .with(headers: { "X-Vault-Token" => "test-token" })
          .to_return(
            status: 200,
            body: "<html>Login page</html>",
            headers: { "Content-Type" => "text/html" }
          )

        error = assert_raises(RuntimeError) do
          HashiCorpVault.read("secret/data/env/r3x")
        end

        assert_match "Vault response missing KV v2 data", error.message
      end

      test "preserves path prefix from VAULT_ADDR" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test/internal/vault"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/internal/vault/v1/secret/data/env/r3x")
          .with(headers: { "X-Vault-Token" => "test-token" })
          .to_return(
            status: 200,
            body: {
              data: {
                data: { "key" => "value" },
                metadata: { version: 1 }
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        result = HashiCorpVault.read("secret/data/env/r3x")

        assert_equal({ "key" => "value" }, result)
      end

      test "configured? returns true when both env vars are set" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"

        assert_equal true, HashiCorpVault.configured?
      end

      test "configured? returns false when VAULT_ADDR is missing" do
        ENV.delete("R3X_VAULT_ADDR")
        ENV["R3X_VAULT_TOKEN"] = "test-token"

        assert_equal false, HashiCorpVault.configured?
      end

      test "configured? returns false when VAULT_TOKEN is missing" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV.delete("R3X_VAULT_TOKEN")

        assert_equal false, HashiCorpVault.configured?
      end

      test "configured? returns false when env vars are blank" do
        ENV["R3X_VAULT_ADDR"] = ""
        ENV["R3X_VAULT_TOKEN"] = ""

        assert_equal false, HashiCorpVault.configured?
      end

      private

      def reset_vault_singleton
        HashiCorpVault.instance_variable_set(:@singleton__instance__, nil)
      end
    end
  end
end

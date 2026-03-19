require "test_helper"

module R3x
  module Client
    class HashiCorpVaultTest < ActiveSupport::TestCase
      setup do
        @original_vault_addr = ENV["VAULT_ADDR"]
        @original_vault_token = ENV["VAULT_TOKEN"]
        reset_vault_singleton
      end

      teardown do
        ENV["VAULT_ADDR"] = @original_vault_addr
        ENV["VAULT_TOKEN"] = @original_vault_token
        WebMock.reset!
        reset_vault_singleton
      end

      test "reads kv v2 data from vault" do
        ENV["VAULT_ADDR"] = "https://vault.test"
        ENV["VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/v1/secret/data/env/r3x")
          .with(headers: { "X-Vault-Token" => "test-token" })
          .to_return(
            status: 200,
            body: {
              data: {
                data: {
                  discord_webhook_url: "https://discord.test",
                  mode: "real"
                },
                metadata: { version: 1 }
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        result = HashiCorpVault.read("secret/data/env/r3x")

        assert_equal({
          "discord_webhook_url" => "https://discord.test",
          "mode" => "real"
        }, result)
      end

      test "raises when required vault config is missing" do
        ENV["VAULT_ADDR"] = nil
        ENV["VAULT_TOKEN"] = nil
        reset_vault_singleton

        error = assert_raises(ArgumentError) do
          HashiCorpVault.read("secret/data/env/r3x")
        end

        assert_equal "Missing VAULT_ADDR", error.message
      end

      test "raises when vault returns a non-success status" do
        ENV["VAULT_ADDR"] = "https://vault.test"
        ENV["VAULT_TOKEN"] = "test-token"
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
        ENV["VAULT_ADDR"] = "https://vault.test"
        ENV["VAULT_TOKEN"] = "test-token"
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

      private

      def reset_vault_singleton
        HashiCorpVault.instance_variable_set(:@singleton__instance__, nil)
      end
    end
  end
end

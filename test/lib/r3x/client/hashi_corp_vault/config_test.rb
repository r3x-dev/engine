require "test_helper"

module R3x
  module Client
    class HashiCorpVault::ConfigTest < ActiveSupport::TestCase
      include VaultTestHelpers

      test "configured? returns true when both env vars are set" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        ENV.delete("R3X_VAULT_AUTH_METHOD")
        ENV.delete("R3X_VAULT_KUBERNETES_ROLE")

        assert_equal true, HashiCorpVault.configured?
      end

      test "configured? returns true when kubernetes auth is configured" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV.delete("R3X_VAULT_TOKEN")
        ENV["R3X_VAULT_AUTH_METHOD"] = "kubernetes"
        ENV["R3X_VAULT_KUBERNETES_ROLE"] = "r3x"

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

      test "configured? raises for unsupported auth method" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV.delete("R3X_VAULT_TOKEN")
        ENV["R3X_VAULT_AUTH_METHOD"] = "kerberos"

        error = assert_raises(ArgumentError) do
          HashiCorpVault.configured?
        end

        assert_equal 'Unsupported Vault auth method: "kerberos"', error.message
      end
    end
  end
end

require "test_helper"

module R3x
  module Client
    class HashiCorpVault::ReadTest < ActiveSupport::TestCase
      include VaultTestHelpers

      test "reads kv v2 data from vault" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"

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
        ENV["R3X_VAULT_AUTH_METHOD"] = nil
        ENV["R3X_VAULT_KUBERNETES_ROLE"] = nil

        error = assert_raises(ArgumentError) do
          HashiCorpVault.read("secret/data/env/r3x")
        end

        assert_equal "Missing R3X_VAULT_ADDR", error.message
      end

      test "reads kv v2 data from vault using kubernetes auth" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV.delete("R3X_VAULT_TOKEN")
        ENV["R3X_VAULT_AUTH_METHOD"] = "kubernetes"
        ENV["R3X_VAULT_KUBERNETES_ROLE"] = "r3x"

        with_service_account_token("k8s-service-account-jwt") do |token_path|
          ENV["R3X_VAULT_KUBERNETES_TOKEN_PATH"] = token_path

          stub_request(:post, "https://vault.test/v1/auth/kubernetes/login")
            .with(
              body: ->(body) { MultiJson.load(body) == { "role" => "r3x", "jwt" => "k8s-service-account-jwt" } }
            )
            .to_return(
              status: 200,
              body: {
                auth: {
                  client_token: "vault-k8s-token",
                  renewable: true,
                  policies: [ "r3x-env-read" ]
                }
              }.to_json,
              headers: { "Content-Type" => "application/json" }
            )

          stub_request(:get, "https://vault.test/v1/secret/data/env/r3x")
            .with(headers: { "X-Vault-Token" => "vault-k8s-token" })
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
      end

      test "raises helpful guidance when kubernetes auth login is denied" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV.delete("R3X_VAULT_TOKEN")
        ENV["R3X_VAULT_AUTH_METHOD"] = "kubernetes"
        ENV["R3X_VAULT_KUBERNETES_ROLE"] = "r3x"

        with_service_account_token(kubernetes_jwt(namespace: "default", service_account_name: "r3x")) do |token_path|
          ENV["R3X_VAULT_KUBERNETES_TOKEN_PATH"] = token_path

          stub_request(:post, "https://vault.test/v1/auth/kubernetes/login")
            .to_return(
              status: 403,
              body: { errors: [ "permission denied" ] }.to_json,
              headers: { "Content-Type" => "application/json" }
            )

          error = assert_raises(RuntimeError) do
            HashiCorpVault.read("secret/data/env/r3x")
          end

          assert_equal <<~MESSAGE.strip, error.message
            Vault Kubernetes auth login failed with status 403: ["permission denied"]. Vault could not exchange the Kubernetes service account token for a Vault token. Check the auth/kubernetes backend configuration (reviewer JWT, Kubernetes host, CA certificate, and issuer settings) and verify that role "r3x" is bound to the expected service account and namespace (default/r3x).
          MESSAGE
        end
      end

      test "raises when vault config is blank string" do
        ENV["R3X_VAULT_ADDR"] = ""
        ENV["R3X_VAULT_TOKEN"] = ""

        error = assert_raises(ArgumentError) do
          HashiCorpVault.read("secret/data/env/r3x")
        end

        assert_equal "Missing R3X_VAULT_ADDR", error.message
      end

      test "raises when vault returns a non-success status" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"

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
    end
  end
end

require "test_helper"
require "tempfile"

module R3x
  module Client
    class HashiCorpVaultTest < ActiveSupport::TestCase
      setup do
        @original_vault_addr = ENV["R3X_VAULT_ADDR"]
        @original_vault_token = ENV["R3X_VAULT_TOKEN"]
        @original_vault_secrets_path = ENV["R3X_VAULT_SECRETS_PATH"]
        @original_vault_auth_method = ENV["R3X_VAULT_AUTH_METHOD"]
        @original_vault_kubernetes_role = ENV["R3X_VAULT_KUBERNETES_ROLE"]
        @original_vault_kubernetes_auth_path = ENV["R3X_VAULT_KUBERNETES_AUTH_PATH"]
        @original_vault_kubernetes_token_path = ENV["R3X_VAULT_KUBERNETES_TOKEN_PATH"]
        reset_vault_singleton
      end

      teardown do
        ENV["R3X_VAULT_ADDR"] = @original_vault_addr
        ENV["R3X_VAULT_TOKEN"] = @original_vault_token
        ENV["R3X_VAULT_SECRETS_PATH"] = @original_vault_secrets_path
        ENV["R3X_VAULT_AUTH_METHOD"] = @original_vault_auth_method
        ENV["R3X_VAULT_KUBERNETES_ROLE"] = @original_vault_kubernetes_role
        ENV["R3X_VAULT_KUBERNETES_AUTH_PATH"] = @original_vault_kubernetes_auth_path
        ENV["R3X_VAULT_KUBERNETES_TOKEN_PATH"] = @original_vault_kubernetes_token_path
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
        ENV["R3X_VAULT_AUTH_METHOD"] = nil
        ENV["R3X_VAULT_KUBERNETES_ROLE"] = nil
        reset_vault_singleton

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
          reset_vault_singleton

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

      test "looks up the current token" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/v1/auth/token/lookup-self")
          .with(headers: { "X-Vault-Token" => "test-token" })
          .to_return(
            status: 200,
            body: {
              data: {
                display_name: "token-r3x-env",
                policies: [ "default", "r3x-env-read" ],
                ttl: 3600,
                renewable: true
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        result = HashiCorpVault.lookup_self

        assert_equal "token-r3x-env", result["display_name"]
        assert_equal [ "default", "r3x-env-read" ], result["policies"]
        assert_equal true, result["renewable"]
      end

      test "renews the current token" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:post, "https://vault.test/v1/auth/token/renew-self")
          .with(headers: { "X-Vault-Token" => "test-token" })
          .to_return(
            status: 200,
            body: {
              auth: {
                lease_duration: 86_400,
                renewable: true,
                policies: [ "r3x-env-read" ]
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        result = HashiCorpVault.renew_self

        assert_equal 86_400, result["lease_duration"]
        assert_equal true, result["renewable"]
        assert_equal [ "r3x-env-read" ], result["policies"]
      end

      test "checks current token capabilities" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:post, "https://vault.test/v1/sys/capabilities-self")
          .with(
            headers: { "X-Vault-Token" => "test-token" },
            body: ->(body) { MultiJson.load(body) == { "paths" => [ "secret/data/env/r3x" ] } }
          )
          .to_return(
            status: 200,
            body: {
              "secret/data/env/r3x" => [ "read" ]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        result = HashiCorpVault.capabilities_self([ "secret/data/env/r3x" ])

        assert_equal [ "read" ], result["secret/data/env/r3x"]
      end

      test "diagnoses vault access without returning secret values" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        ENV["R3X_VAULT_SECRETS_PATH"] = "secret/data/env/r3x"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/v1/auth/token/lookup-self")
          .to_return(
            status: 200,
            body: {
              data: {
                display_name: "token-r3x-env",
                policies: [ "r3x-env-read" ],
                ttl: 3600,
                renewable: true,
                period: 86_400,
                explicit_max_ttl: 0,
                id: "test-token"
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:post, "https://vault.test/v1/sys/capabilities-self")
          .to_return(
            status: 200,
            body: {
              "secret/data/env/r3x" => [ "read" ],
              "auth/token/lookup-self" => [ "read" ],
              "auth/token/renew-self" => [ "update" ]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:post, "https://vault.test/v1/auth/token/renew-self")
          .to_return(
            status: 200,
            body: {
              auth: {
                lease_duration: 86_400,
                renewable: true,
                policies: [ "r3x-env-read" ],
                client_token: "test-token"
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:get, "https://vault.test/v1/secret/data/env/r3x")
          .to_return(
            status: 200,
            body: {
              data: {
                data: {
                  "GEMINI_API_KEY" => "secret-gemini-key",
                  "OPENAI_API_KEY" => "secret-openai-key"
                }
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        result = HashiCorpVault.diagnose

        assert_equal "https://vault.test", result[:vault_addr]
        assert_equal "secret/data/env/r3x", result[:secret_path]
        assert_equal "token-r3x-env", result[:token]["display_name"]
        assert_equal true, result[:token]["renewable"]
        assert_equal [ "read" ], result[:capabilities]["secret/data/env/r3x"]
        assert_equal 86_400, result[:renewal]["lease_duration"]
        assert_equal [ "GEMINI_API_KEY", "OPENAI_API_KEY" ], result[:secret][:keys]

        refute_includes result.to_s, "secret-gemini-key"
        refute_includes result.to_s, "secret-openai-key"
        refute_includes result.to_s, "test-token"
      end

      test "diagnose skips renewal for non-renewable token" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        ENV["R3X_VAULT_SECRETS_PATH"] = "secret/data/env/r3x"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/v1/auth/token/lookup-self")
          .to_return(
            status: 200,
            body: {
              data: {
                display_name: "token-r3x-env",
                policies: [ "r3x-env-read" ],
                ttl: 3600,
                renewable: false,
                period: nil,
                explicit_max_ttl: 0,
                id: "test-token"
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:post, "https://vault.test/v1/sys/capabilities-self")
          .to_return(
            status: 200,
            body: {
              "secret/data/env/r3x" => [ "read" ],
              "auth/token/lookup-self" => [ "read" ],
              "auth/token/renew-self" => [ "update" ]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:get, "https://vault.test/v1/secret/data/env/r3x")
          .to_return(
            status: 200,
            body: {
              data: {
                data: {
                  "GEMINI_API_KEY" => "secret-gemini-key"
                }
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        result = HashiCorpVault.diagnose

        assert_equal false, result[:token]["renewable"]
        assert_nil result[:renewal]
        assert_equal [ "GEMINI_API_KEY" ], result[:secret][:keys]

        assert_not_requested :post, "https://vault.test/v1/auth/token/renew-self"
      end

      test "raises when token lookup fails" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        reset_vault_singleton

        stub_request(:get, "https://vault.test/v1/auth/token/lookup-self")
          .to_return(
            status: 403,
            body: { errors: [ "permission denied" ] }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        error = assert_raises(RuntimeError) do
          HashiCorpVault.lookup_self
        end

        assert_equal 'Vault request failed with status 403: ["permission denied"]', error.message
      end

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

      private

      def with_service_account_token(token)
        file = Tempfile.new("vault-kubernetes-token")
        file.write(token)
        file.flush

        yield file.path
      ensure
        file&.close!
      end

      def reset_vault_singleton
        HashiCorpVault.instance_variable_set(:@singleton__instance__, nil)
      end
    end
  end
end

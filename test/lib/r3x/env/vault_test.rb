require "test_helper"

module R3x
  class Env::VaultTest < ActiveSupport::TestCase
    include VaultTestHelpers

    test "load_from_vault returns empty hash when vault is not configured" do
      ENV.delete("R3X_VAULT_ADDR")
      ENV.delete("R3X_VAULT_TOKEN")
      ENV.delete("R3X_VAULT_AUTH_METHOD")
      ENV.delete("R3X_VAULT_KUBERNETES_ROLE")

      assert_equal({}, Env.load_from_vault("secret/data/test"))
    end

    test "load_from_vault raises RuntimeError when vault returns R3X_ prefixed key" do
      ENV["R3X_VAULT_ADDR"] = "https://vault.test"
      ENV["R3X_VAULT_TOKEN"] = "test-token"

      stub_request(:get, "https://vault.test/v1/secret/data/test")
        .with(headers: { "X-Vault-Token" => "test-token" })
        .to_return(
          status: 200,
          body: {
            data: {
              data: {
                "GEMINI_API_KEY_TEST" => "secret-value",
                "R3X_DISCORD_WEBHOOK_URL" => "https://discord.example.test"
              }
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      error = assert_raises(RuntimeError) do
        Env.load_from_vault("secret/data/test")
      end

      assert_match(/starts with reserved prefix/, error.message)
      assert_match(/R3X_DISCORD_WEBHOOK_URL/, error.message)
    end

    test "load_from_vault loads secrets using kubernetes auth" do
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

        stub_request(:get, "https://vault.test/v1/secret/data/test")
          .with(headers: { "X-Vault-Token" => "vault-k8s-token" })
          .to_return(
            status: 200,
            body: {
              data: {
                data: {
                  "GEMINI_API_KEY_TEST" => true
                }
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        assert_equal({ "GEMINI_API_KEY_TEST" => true }, Env.load_from_vault("secret/data/test"))
      end
    end

    test "load_from_vault raises for unsupported auth method" do
      ENV["R3X_VAULT_ADDR"] = "https://vault.test"
      ENV.delete("R3X_VAULT_TOKEN")
      ENV["R3X_VAULT_AUTH_METHOD"] = "kerberos"

      error = assert_raises(ArgumentError) do
        Env.load_from_vault("secret/data/test")
      end

      assert_equal 'Unsupported Vault auth method: "kerberos"', error.message
    end

    test "load_from_vault raises when kubernetes auth is selected but incomplete" do
      ENV["R3X_VAULT_ADDR"] = "https://vault.test"
      ENV.delete("R3X_VAULT_TOKEN")
      ENV["R3X_VAULT_AUTH_METHOD"] = "kubernetes"
      ENV.delete("R3X_VAULT_KUBERNETES_ROLE")

      error = assert_raises(ArgumentError) do
        Env.load_from_vault("secret/data/test")
      end

      assert_equal "Missing R3X_VAULT_KUBERNETES_ROLE", error.message
    end

    test "load_from_vault raises when kubernetes token file is missing" do
      ENV["R3X_VAULT_ADDR"] = "https://vault.test"
      ENV.delete("R3X_VAULT_TOKEN")
      ENV["R3X_VAULT_AUTH_METHOD"] = "kubernetes"
      ENV["R3X_VAULT_KUBERNETES_ROLE"] = "r3x"
      ENV["R3X_VAULT_KUBERNETES_TOKEN_PATH"] = "/tmp/does-not-exist-r3x-vault-token"

      error = assert_raises(RuntimeError) do
        Env.load_from_vault("secret/data/test")
      end

      assert_match(/Vault Kubernetes service account token not found/, error.message)
    end
  end
end

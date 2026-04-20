require "test_helper"

module R3x
  module Client
    class HashiCorpVault::DiagnoseTest < ActiveSupport::TestCase
      include VaultTestHelpers

      test "diagnoses vault access without returning secret values" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        ENV["R3X_VAULT_SECRETS_PATH"] = "secret/data/env/r3x"

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
              "auth/token/lookup-self" => [ "read" ]
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
        assert_equal [ "GEMINI_API_KEY", "OPENAI_API_KEY" ], result[:secret][:keys]

        refute_includes result.to_s, "secret-gemini-key"
        refute_includes result.to_s, "secret-openai-key"
        refute_includes result.to_s, "test-token"
      end

      test "diagnose remains read-only for renewable token" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        ENV["R3X_VAULT_SECRETS_PATH"] = "secret/data/env/r3x"

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
                explicit_max_ttl: 0
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:post, "https://vault.test/v1/sys/capabilities-self")
          .to_return(
            status: 200,
            body: {
              "secret/data/env/r3x" => [ "read" ],
              "auth/token/lookup-self" => [ "read" ]
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

        assert_equal true, result[:token]["renewable"]
        assert_equal [ "read" ], result[:capabilities]["auth/token/lookup-self"]
      end

      test "raises when token lookup fails" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"
        ENV["R3X_VAULT_SECRETS_PATH"] = "secret/data/env/r3x"

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
    end
  end
end

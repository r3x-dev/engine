require "test_helper"

module R3x
  module Client
    class HashiCorpVault::OperationsTest < ActiveSupport::TestCase
      include VaultTestHelpers

      test "looks up the current token" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"

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

      test "checks current token capabilities" do
        ENV["R3X_VAULT_ADDR"] = "https://vault.test"
        ENV["R3X_VAULT_TOKEN"] = "test-token"

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
    end
  end
end

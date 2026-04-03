require "test_helper"

module R3x
  class EnvTest < ActiveSupport::TestCase
    setup do
      @original = ENV["R3X_TEST_ENV_VAR"]
    end

    teardown do
      ENV["R3X_TEST_ENV_VAR"] = @original
    end

    # fetch tests

    test "returns value when present" do
      ENV["R3X_TEST_ENV_VAR"] = "https://example.com"

      assert_equal "https://example.com", Env.fetch("R3X_TEST_ENV_VAR")
    end

    test "raises when missing" do
      ENV.delete("R3X_TEST_ENV_VAR")

      error = assert_raises(ArgumentError) { Env.fetch!("R3X_TEST_ENV_VAR") }
      assert_equal "Missing R3X_TEST_ENV_VAR", error.message
    end

    test "raises when blank" do
      ENV["R3X_TEST_ENV_VAR"] = ""

      error = assert_raises(ArgumentError) { Env.fetch!("R3X_TEST_ENV_VAR") }
      assert_equal "Missing R3X_TEST_ENV_VAR", error.message
    end

    test "raises when whitespace only" do
      ENV["R3X_TEST_ENV_VAR"] = "   "

      error = assert_raises(ArgumentError) { Env.fetch!("R3X_TEST_ENV_VAR") }
      assert_equal "Missing R3X_TEST_ENV_VAR", error.message
    end

    # secure_fetch with String prefix

    test "secure_fetch with string prefix returns value when key starts with prefix" do
      ENV["GEMINI_API_KEY_TEST"] = "AIza-test-key"

      assert_equal "AIza-test-key", Env.secure_fetch("GEMINI_API_KEY_TEST", prefix: "GEMINI_API_KEY_")
    ensure
      ENV.delete("GEMINI_API_KEY_TEST")
    end

    test "secure_fetch with string prefix rejects key not starting with prefix" do
      ENV["OTHER_KEY_TEST"] = "some-value"

      error = assert_raises(ArgumentError) do
        Env.secure_fetch("OTHER_KEY_TEST", prefix: "GEMINI_API_KEY_")
      end

      assert_match(/must start with/, error.message)
    ensure
      ENV.delete("OTHER_KEY_TEST")
    end

    test "secure_fetch with string prefix raises when value is missing" do
      ENV.delete("GEMINI_API_KEY_MISSING")

      error = assert_raises(ArgumentError) do
        Env.secure_fetch("GEMINI_API_KEY_MISSING", prefix: "GEMINI_API_KEY_")
      end

      assert_equal "Missing GEMINI_API_KEY_MISSING", error.message
    end

    # secure_fetch with Regexp prefix

    test "secure_fetch with regexp returns value when key matches" do
      ENV["GEMINI_API_KEY_MICHAL"] = "AIza-valid"

      assert_equal "AIza-valid", Env.secure_fetch("GEMINI_API_KEY_MICHAL", prefix: /\AGEMINI_API_KEY_[A-Z0-9_]+\z/)
    ensure
      ENV.delete("GEMINI_API_KEY_MICHAL")
    end

    test "secure_fetch with regexp rejects key not matching pattern" do
      ENV["VAULT_TOKEN"] = "hvs-secret"

      error = assert_raises(ArgumentError) do
        Env.secure_fetch("VAULT_TOKEN", prefix: /\AGEMINI_API_KEY_[A-Z0-9_]+\z/)
      end

      assert_match(/must match/, error.message)
    ensure
      ENV.delete("VAULT_TOKEN")
    end

    test "secure_fetch with regexp rejects lowercase in key" do
      ENV["GEMINI_API_KEY_michal"] = "AIza-test"

      error = assert_raises(ArgumentError) do
        Env.secure_fetch("GEMINI_API_KEY_michal", prefix: /\AGEMINI_API_KEY_[A-Z0-9_]+\z/)
      end

      assert_match(/must match/, error.message)
    ensure
      ENV.delete("GEMINI_API_KEY_michal")
    end

    test "secure_fetch with regexp rejects injection characters" do
      ENV["GEMINI_API_KEY_TEST;INJECTED"] = "AIza-test"

      error = assert_raises(ArgumentError) do
        Env.secure_fetch("GEMINI_API_KEY_TEST;INJECTED", prefix: /\AGEMINI_API_KEY_[A-Z0-9_]+\z/)
      end

      assert_match(/must match/, error.message)
    ensure
      ENV.delete("GEMINI_API_KEY_TEST;INJECTED")
    end

    test "secure_fetch with regexp rejects path traversal" do
      ENV["GEMINI_API_KEY_../../../ETC"] = "AIza-test"

      error = assert_raises(ArgumentError) do
        Env.secure_fetch("GEMINI_API_KEY_../../../ETC", prefix: /\AGEMINI_API_KEY_[A-Z0-9_]+\z/)
      end

      assert_match(/must match/, error.message)
    ensure
      ENV.delete("GEMINI_API_KEY_../../../ETC")
    end

    test "secure_fetch raises on unsupported prefix type" do
      ENV["SOME_KEY"] = "value"

      error = assert_raises(ArgumentError) do
        Env.secure_fetch("SOME_KEY", prefix: 42)
      end

      assert_match(/must be a String or Regexp/, error.message)
    ensure
      ENV.delete("SOME_KEY")
    end

    # fetch_boolean tests

    test "fetch_boolean returns true for truthy values" do
      %w[1 true yes on].each do |value|
        ENV["R3X_TEST_ENV_VAR"] = value
        assert_equal true, Env.fetch_boolean("R3X_TEST_ENV_VAR"), "Expected true for #{value.inspect}"
      end
    ensure
      ENV.delete("R3X_TEST_ENV_VAR")
    end

    test "fetch_boolean returns false for falsy values" do
      %w[0 false no off].each do |value|
        ENV["R3X_TEST_ENV_VAR"] = value
        assert_equal false, Env.fetch_boolean("R3X_TEST_ENV_VAR"), "Expected false for #{value.inspect}"
      end
    ensure
      ENV.delete("R3X_TEST_ENV_VAR")
    end

    test "fetch_boolean returns nil when env var is missing" do
      ENV.delete("R3X_TEST_ENV_VAR")
      assert_nil Env.fetch_boolean("R3X_TEST_ENV_VAR")
    end

    test "fetch_boolean returns nil when env var is blank" do
      ENV["R3X_TEST_ENV_VAR"] = ""
      assert_nil Env.fetch_boolean("R3X_TEST_ENV_VAR")
    ensure
      ENV.delete("R3X_TEST_ENV_VAR")
    end

    test "fetch_boolean raises on invalid value" do
      ENV["R3X_TEST_ENV_VAR"] = "invalid"
      error = assert_raises(ArgumentError) { Env.fetch_boolean("R3X_TEST_ENV_VAR") }
      assert_match(/Invalid boolean/, error.message)
      assert_match(/R3X_TEST_ENV_VAR/, error.message)
    ensure
      ENV.delete("R3X_TEST_ENV_VAR")
    end

    test "fetch_boolean is case-insensitive" do
      ENV["R3X_TEST_ENV_VAR"] = "TRUE"
      assert_equal true, Env.fetch_boolean("R3X_TEST_ENV_VAR")

      ENV["R3X_TEST_ENV_VAR"] = "FALSE"
      assert_equal false, Env.fetch_boolean("R3X_TEST_ENV_VAR")
    ensure
      ENV.delete("R3X_TEST_ENV_VAR")
    end

    # load_from_vault tests

    test "load_from_vault returns empty hash when vault is not configured" do
      original_addr = ENV["R3X_VAULT_ADDR"]
      original_token = ENV["R3X_VAULT_TOKEN"]
      ENV.delete("R3X_VAULT_ADDR")
      ENV.delete("R3X_VAULT_TOKEN")

      assert_equal({}, Env.load_from_vault("secret/data/test"))
    ensure
      ENV["R3X_VAULT_ADDR"] = original_addr
      ENV["R3X_VAULT_TOKEN"] = original_token
    end

    test "load_from_vault raises RuntimeError when vault returns R3X_ prefixed key" do
      original_addr = ENV["R3X_VAULT_ADDR"]
      original_token = ENV["R3X_VAULT_TOKEN"]
      ENV["R3X_VAULT_ADDR"] = "https://vault.test"
      ENV["R3X_VAULT_TOKEN"] = "test-token"
      reset_vault_singleton

      stub_request(:get, "https://vault.test/v1/auth/token/lookup-self")
        .to_return(status: 200, body: { data: { id: "test-token" } }.to_json,
          headers: { "Content-Type" => "application/json" })

      stub_request(:get, "https://vault.test/v1/secret/data/test")
        .to_return(
          status: 200,
          body: {
            data: {
              data: {
                "GEMINI_API_KEY_MICHAL" => "AIza-vault-key",
                "R3X_DISCORD_WEBHOOK_URL" => "https://discord.should-not-load",
                "OPENAI_API_KEY_TEST" => "sk-vault-key"
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
    ensure
      ENV["R3X_VAULT_ADDR"] = original_addr
      ENV["R3X_VAULT_TOKEN"] = original_token
      reset_vault_singleton
      WebMock.reset!
    end

    private

    def reset_vault_singleton
      R3x::Client::HashiCorpVault.instance_variable_set(:@singleton__instance__, nil)
    end
  end
end

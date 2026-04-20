require "test_helper"
require "tempfile"

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
      ENV["GEMINI_API_KEY_TEST"] = "AIza-valid"

      assert_equal "AIza-valid", Env.secure_fetch("GEMINI_API_KEY_TEST", prefix: /\AGEMINI_API_KEY_[A-Z0-9_]+\z/)
    ensure
      ENV.delete("GEMINI_API_KEY_TEST")
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
      ENV["GEMINI_API_KEY_test"] = "AIza-test"

      error = assert_raises(ArgumentError) do
        Env.secure_fetch("GEMINI_API_KEY_test", prefix: /\AGEMINI_API_KEY_[A-Z0-9_]+\z/)
      end

      assert_match(/must match/, error.message)
    ensure
      ENV.delete("GEMINI_API_KEY_test")
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

    private
  end
end

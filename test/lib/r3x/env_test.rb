require "test_helper"

module R3x
  class EnvTest < ActiveSupport::TestCase
    setup do
      @original = ENV["R3X_TEST_ENV_VAR"]
    end

    teardown do
      ENV["R3X_TEST_ENV_VAR"] = @original
    end

    test "returns value when present" do
      ENV["R3X_TEST_ENV_VAR"] = "https://example.com"

      assert_equal "https://example.com", Env.fetch("R3X_TEST_ENV_VAR")
    end

    test "raises when missing" do
      ENV.delete("R3X_TEST_ENV_VAR")

      error = assert_raises(ArgumentError) { Env.fetch("R3X_TEST_ENV_VAR") }
      assert_equal "Missing R3X_TEST_ENV_VAR", error.message
    end

    test "raises when blank" do
      ENV["R3X_TEST_ENV_VAR"] = ""

      error = assert_raises(ArgumentError) { Env.fetch("R3X_TEST_ENV_VAR") }
      assert_equal "Missing R3X_TEST_ENV_VAR", error.message
    end

    test "raises when whitespace only" do
      ENV["R3X_TEST_ENV_VAR"] = "   "

      error = assert_raises(ArgumentError) { Env.fetch("R3X_TEST_ENV_VAR") }
      assert_equal "Missing R3X_TEST_ENV_VAR", error.message
    end
  end
end

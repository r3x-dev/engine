require "test_helper"

module R3x
  class PolicyTest < ActiveSupport::TestCase
    setup do
      @original_global = ENV["R3X_DRY_RUN"]
      @original_gmail = ENV["R3X_GMAIL_DRY_RUN"]
    end

    teardown do
      ENV["R3X_DRY_RUN"] = @original_global
      ENV["R3X_GMAIL_DRY_RUN"] = @original_gmail
    end

    test "defaults to dry run in test environment" do
      assert_equal true, Policy.default_dry_run_for(:gmail)
    end

    test "dry_run_for prefers explicit value" do
      assert_equal false, Policy.dry_run_for(:gmail, false)
      assert_equal true, Policy.dry_run_for(:gmail, true)
    end

    test "real_delivery_for? inverts dry run" do
      assert_equal true, Policy.real_delivery_for?(:gmail, false)
      assert_equal false, Policy.real_delivery_for?(:gmail, true)
    end

    test "defaults to real delivery in production" do
      original = Rails.method(:env)
      Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new("production") }

      assert_equal false, Policy.default_dry_run_for(:gmail)
    ensure
      Rails.define_singleton_method(:env, original)
    end

    test "specific env override wins" do
      ENV["R3X_GMAIL_DRY_RUN"] = "false"

      assert_equal false, Policy.default_dry_run_for(:gmail)
    end

    test "global env override wins when specific is absent" do
      ENV.delete("R3X_GMAIL_DRY_RUN")
      ENV["R3X_DRY_RUN"] = "false"

      assert_equal false, Policy.default_dry_run_for(:discord)
    end

    test "rejects invalid boolean values" do
      ENV["R3X_GMAIL_DRY_RUN"] = "maybe"

      error = assert_raises(ArgumentError) do
        Policy.default_dry_run_for(:gmail)
      end

      assert_equal 'Invalid boolean for dry run: "maybe"', error.message
    end
  end
end

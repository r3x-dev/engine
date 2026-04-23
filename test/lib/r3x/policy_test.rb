require "test_helper"

module R3x
  class PolicyTest < ActiveSupport::TestCase
    setup do
      @original_global = ENV["R3X_DRY_RUN"]
      @original_gmail = ENV["R3X_GMAIL_DRY_RUN"]
      @original_skip_cache = ENV["R3X_SKIP_CACHE"]
    end

    teardown do
      ENV["R3X_DRY_RUN"] = @original_global
      ENV["R3X_GMAIL_DRY_RUN"] = @original_gmail
      ENV["R3X_SKIP_CACHE"] = @original_skip_cache
    end

    test "defaults to dry run in test environment" do
      Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("test"))

      with_env("R3X_DRY_RUN" => nil, "R3X_GMAIL_DRY_RUN" => nil) do
        assert_equal true, Policy.default_dry_run_for(:gmail)
      end
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
      Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

      assert_equal false, Policy.default_dry_run_for(:gmail)
    end

    test "specific env override wins" do
      with_env("R3X_GMAIL_DRY_RUN" => "false") do
        assert_equal false, Policy.default_dry_run_for(:gmail)
      end
    end

    test "global env override wins when specific is absent" do
      with_env("R3X_GMAIL_DRY_RUN" => nil, "R3X_DRY_RUN" => "false") do
        assert_equal false, Policy.default_dry_run_for(:discord)
      end
    end

    test "rejects invalid boolean values" do
      with_env("R3X_GMAIL_DRY_RUN" => "maybe") do
        error = assert_raises(ArgumentError) do
          Policy.default_dry_run_for(:gmail)
        end

        assert_equal 'Invalid boolean for R3X_GMAIL_DRY_RUN: "maybe"', error.message
      end
    end

    test "skip_cache? defaults to false" do
      assert_equal false, Policy.skip_cache?
    end

    test "skip_cache? reads env override" do
      with_env("R3X_SKIP_CACHE" => "true") do
        assert_equal true, Policy.skip_cache?
      end
    end

    test "skip_cache? rejects invalid boolean values" do
      with_env("R3X_SKIP_CACHE" => "maybe") do
        error = assert_raises(ArgumentError) do
          Policy.skip_cache?
        end

        assert_equal 'Invalid boolean for R3X_SKIP_CACHE: "maybe"', error.message
      end
    end

    private

    def with_env(values)
      old_values = {}

      values.each do |key, value|
        old_values[key] = ENV[key]

        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end

      yield
    ensure
      old_values.each do |key, value|
        ENV[key] = value
      end
    end
  end
end

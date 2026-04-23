require "test_helper"

module R3x
  class RuntimeProfileTest < ActiveSupport::TestCase
    setup do
      @original_runtime_profile = ENV.delete("R3X_RUNTIME_PROFILE")
      RuntimeProfile.instance_variable_set(:@current, nil)
    end

    teardown do
      RuntimeProfile.instance_variable_set(:@current, nil)

      if @original_runtime_profile
        ENV["R3X_RUNTIME_PROFILE"] = @original_runtime_profile
      else
        ENV.delete("R3X_RUNTIME_PROFILE")
      end
    end

    test "defaults to web profile" do
      assert_equal "web", RuntimeProfile.current
      assert_equal [ :web ], RuntimeProfile.bundler_groups
      refute RuntimeProfile.jobs?
      refute RuntimeProfile.workflow_cli?
      refute RuntimeProfile.headless?
    end

    test "recognizes jobs profile" do
      ENV["R3X_RUNTIME_PROFILE"] = "jobs"

      assert_equal "jobs", RuntimeProfile.current
      assert_equal [], RuntimeProfile.bundler_groups
      assert RuntimeProfile.jobs?
      refute RuntimeProfile.workflow_cli?
      assert RuntimeProfile.headless?
    end

    test "recognizes workflow_cli profile" do
      ENV["R3X_RUNTIME_PROFILE"] = "workflow_cli"

      assert_equal "workflow_cli", RuntimeProfile.current
      assert_equal [], RuntimeProfile.bundler_groups
      refute RuntimeProfile.jobs?
      assert RuntimeProfile.workflow_cli?
      assert RuntimeProfile.headless?
    end

    test "rejects unsupported profiles" do
      ENV["R3X_RUNTIME_PROFILE"] = "sidekiq"

      error = assert_raises(ArgumentError) do
        RuntimeProfile.current
      end

      assert_includes error.message, "Unsupported R3X_RUNTIME_PROFILE"
    end
  end
end

require "test_helper"

module R3x
  class RuntimeProfileTest < ActiveSupport::TestCase
    test "defaults to web profile" do
      assert_equal "web", RuntimeProfile.current({})
      assert_equal [ :web ], RuntimeProfile.bundler_groups({})
      refute RuntimeProfile.jobs?({})
      refute RuntimeProfile.workflow_cli?({})
      refute RuntimeProfile.headless?({})
    end

    test "recognizes jobs profile" do
      env = { "R3X_RUNTIME_PROFILE" => "jobs" }

      assert_equal "jobs", RuntimeProfile.current(env)
      assert_equal [], RuntimeProfile.bundler_groups(env)
      assert RuntimeProfile.jobs?(env)
      refute RuntimeProfile.workflow_cli?(env)
      assert RuntimeProfile.headless?(env)
    end

    test "recognizes workflow_cli profile" do
      env = { "R3X_RUNTIME_PROFILE" => "workflow_cli" }

      assert_equal "workflow_cli", RuntimeProfile.current(env)
      assert_equal [], RuntimeProfile.bundler_groups(env)
      refute RuntimeProfile.jobs?(env)
      assert RuntimeProfile.workflow_cli?(env)
      assert RuntimeProfile.headless?(env)
    end

    test "rejects unsupported profiles" do
      error = assert_raises(ArgumentError) do
        RuntimeProfile.current({ "R3X_RUNTIME_PROFILE" => "sidekiq" })
      end

      assert_includes error.message, "Unsupported R3X_RUNTIME_PROFILE"
    end
  end
end

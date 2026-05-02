require "test_helper"

module R3x
  class LogTest < ActiveSupport::TestCase
    test "defaults to plain when env is unset" do
      with_env("R3X_LOG_FORMAT" => nil) do
        assert_equal "plain", Log.format
        assert Log.plain?
        refute Log.json?
      end
    end

    test "defaults to plain when env is blank" do
      with_env("R3X_LOG_FORMAT" => "") do
        assert_equal "plain", Log.format
      end
    end

    test "returns json when env is json" do
      with_env("R3X_LOG_FORMAT" => "json") do
        assert_equal "json", Log.format
        assert Log.json?
        refute Log.plain?
      end
    end

    test "returns plain when env is plain" do
      with_env("R3X_LOG_FORMAT" => "plain") do
        assert_equal "plain", Log.format
      end
    end

    test "raises on unsupported format" do
      with_env("R3X_LOG_FORMAT" => "xml") do
        error = assert_raises(ArgumentError) { Log.format }
        assert_equal "Unsupported R3X_LOG_FORMAT: \"xml\". Use 'json' or 'plain'.", error.message
      end
    end

    test "builds structured log tags" do
      assert_equal "r3x.run_active_job_id=aj-123", Log.tag(Log::RUN_ACTIVE_JOB_ID_TAG, "aj-123")
      assert_nil Log.tag(Log::RUN_ACTIVE_JOB_ID_TAG, nil)
    end

    private

    def with_env(overrides)
      original = {}
      overrides.each do |key, value|
        original[key] = ENV[key]
        ENV[key] = value
      end
      yield
    ensure
      original.each do |key, value|
        ENV[key] = value
      end
    end
  end
end

require "test_helper"

module R3x
  class LogTest < ActiveSupport::TestCase
    test "defaults to plain when env is unset" do
      with_env("R3X_LOG_FORMAT" => nil) do
        Log.instance_variable_set(:@format, nil)
        assert_equal "plain", Log.format
        assert Log.plain?
        refute Log.json?
      end
    end

    test "defaults to plain when env is blank" do
      with_env("R3X_LOG_FORMAT" => "") do
        Log.instance_variable_set(:@format, nil)
        assert_equal "plain", Log.format
      end
    end

    test "returns json when env is json" do
      with_env("R3X_LOG_FORMAT" => "json") do
        Log.instance_variable_set(:@format, nil)
        assert_equal "json", Log.format
        assert Log.json?
        refute Log.plain?
      end
    end

    test "returns plain when env is plain" do
      with_env("R3X_LOG_FORMAT" => "plain") do
        Log.instance_variable_set(:@format, nil)
        assert_equal "plain", Log.format
      end
    end

    test "raises on unsupported format" do
      with_env("R3X_LOG_FORMAT" => "xml") do
        Log.instance_variable_set(:@format, nil)
        error = assert_raises(ArgumentError) { Log.format }
        assert_equal "Unsupported R3X_LOG_FORMAT: \"xml\". Use 'json' or 'plain'.", error.message
      end
    end

    test "memoizes format" do
      with_env("R3X_LOG_FORMAT" => "json") do
        Log.instance_variable_set(:@format, nil)
        Log.format
        ENV["R3X_LOG_FORMAT"] = "plain"
        assert_equal "json", Log.format
      end
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
      Log.instance_variable_set(:@format, nil)
    end
  end
end

require "test_helper"
require "erb"
require "yaml"

class DatabaseConfigTest < ActiveSupport::TestCase
  test "uses enough connections for Solid Queue worker threads" do
    with_env("RAILS_MAX_THREADS" => "1", "JOB_THREADS" => "1") do
      production = database_config.fetch("production")

      assert_equal 3, production.fetch("primary").fetch("max_connections")
    end
  end

  test "keeps the web pool tied to rails max threads when job threads are absent" do
    with_env("RAILS_MAX_THREADS" => "7", "JOB_THREADS" => nil) do
      development = database_config.fetch("development")

      assert_equal 7, development.fetch("primary").fetch("max_connections")
    end
  end

  private

  def database_config
    YAML.safe_load(
      ERB.new(Rails.root.join("config/database.yml").read).result,
      aliases: true
    )
  end

  def with_env(values)
    originals = values.each_with_object({}) { |(key, _), memo| memo[key] = ENV[key] }

    values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    originals.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end

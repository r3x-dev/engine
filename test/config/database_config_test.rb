# frozen_string_literal: true

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

  test "uses SQLite for tests by default" do
    with_env("R3X_TEST_DATABASE_URL" => nil) do
      test_database = database_config.fetch("test").fetch("primary")

      assert_equal "sqlite3", test_database.fetch("adapter")
      assert_equal "storage/test.sqlite3", test_database.fetch("database")
      assert_not test_database.key?("url")
    end
  end

  test "uses the explicit PostgreSQL test database URL" do
    url = "postgresql://r3x:secret@127.0.0.1:5432/r3x_test"

    with_env("R3X_TEST_DATABASE_URL" => url) do
      test_database = database_config.fetch("test").fetch("primary")

      assert_equal url, test_database.fetch("url")
      assert_not test_database.key?("adapter")
      assert_not test_database.key?("database")
    end
  end

  private

  def database_config
    YAML.safe_load(
      ERB.new(Rails.root.join("config/database.yml").read).result,
      aliases: true,
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

# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

class DiscordSchedulerTest < ActiveSupport::TestCase
  test "jobs-scheduler exits on invalid Discord config and on a fatal polling error" do
    Dir.mktmpdir do |dir|
      env = {
        "RAILS_ENV"                      => "production",
        "SECRET_KEY_BASE"                => "scheduler-test-secret",
        "R3X_SKIP_VAULT_ENV_LOAD"        => "true",
        "R3X_WORKFLOW_PATHS"             => Rails.root.join("test/fixtures/discord_polling").to_s,
        "R3X_DATABASE_URL"               => nil,
        "R3X_DATABASE_PATH"              => File.join(dir, "scheduler.sqlite3"),
        "R3X_DISCORD_ALLOWED_AUTHOR_IDS" => "1",
        "DISCORD_BOT_TOKEN"              => nil,
      }
      output, status = Open3.capture2e(env, "bin/rails", "runner",
        'load Rails.root.join("db/schema.rb"); ActiveRecord::Base.connection.drop_table(:trigger_cursors)')

      assert_predicate status, :success?, output

      output, status = Open3.capture2e(env, "timeout", "-k", "3", "15", "bin/jobs-scheduler")

      assert_equal 1, status.exitstatus, output
      assert_includes output, "Missing DISCORD_BOT_TOKEN"

      output, status = Open3.capture2e(env.merge("DISCORD_BOT_TOKEN" => "test"), "timeout", "-k", "3", "15", "bin/jobs-scheduler")

      assert_equal 1, status.exitstatus, output
      assert_includes output, "Fatal Discord polling error"
      assert_match(/(?:no such table|Could not find table).*trigger_cursors/i, output)
    end
  end
end

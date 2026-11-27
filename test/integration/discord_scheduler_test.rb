# frozen_string_literal: true

require "test_helper"
require "open3"
require "timeout"
require "tmpdir"

class DiscordSchedulerTest < ActiveSupport::TestCase
  test "jobs-scheduler exits on invalid Discord config and on a fatal polling error" do
    with_scheduler_database do |env, _dir|
      assert_discord_scheduler_failures(env, "bin/jobs-scheduler")
    end
  end

  %w[fork async].each do |mode|
    test "scheduler in #{mode} mode finishes an in-flight Discord read before exiting" do
      with_scheduler_database(broken_cursor: false) do |env, dir|
        env["DISCORD_BOT_TOKEN"] = "test"
        env["SOLID_QUEUE_SUPERVISOR_MODE"] = mode
        pack = File.join(dir, "inbox")
        Dir.mkdir(pack)
        File.write(File.join(pack, "workflow.rb"), <<~RUBY)
          require #{Rails.root.join("test/fixtures/discord_polling/inbox/workflow.rb").to_s.inspect}
          require "webmock"
          require "httpx/adapters/webmock"
          WebMock.enable!
          WebMock.stub_request(:get, "https://discord.com/api/v10/channels/42/messages?limit=1").to_return do
            puts "Discord read started"
            STDIN.readline
            { status: 200, headers: { "Content-Type" => "application/json" }, body: '[{"id":"123"}]' }
          end
          SolidQueue::Scheduler.before_shutdown(prepend: true) { puts "Scheduler is stopping" }
        RUBY
        env["R3X_WORKFLOW_PATHS"] = pack
        command = mode == "async" ? puma_command(dir) : ["bin/jobs-scheduler"]
        Open3.popen2e(env, *command, pgroup: true) do |input, stream, child|
          output = +""
          Timeout.timeout(15) do
            stream.each_line do |line|
              output << line
              Process.kill(:INT, child.pid) if line.include?("Discord read started")
              break if line.include?("Scheduler is stopping")
            end

            assert_includes output, "Scheduler is stopping"
            assert_nil child.join(0.5), "Scheduler exited with the Discord response still pending"
            input.puts "release"
            output << stream.read

            assert_predicate child.value, :success?, output
          end
        ensure
          Process.kill(:KILL, -child.pid) if child.alive?
        end

        SQLite3::Database.new(env.fetch("R3X_DATABASE_PATH"), readonly: true) do |database|
          assert_equal "123", database.get_first_value("SELECT message_id FROM trigger_cursors")
        end
      end
    end
  end

  test "combined Puma in fork mode exits on invalid Discord config and on a fatal polling error" do
    with_scheduler_database do |env, dir|
      assert_discord_scheduler_failures(env, *puma_command(dir))
    end
  end

  test "combined Puma in async mode stops gracefully and exits one on invalid Discord config" do
    with_scheduler_database do |env, dir|
      env["SOLID_QUEUE_SUPERVISOR_MODE"] = "async"
      output, status = Open3.capture2e(env, "timeout", "-k", "3", "15", *puma_command(dir))

      assert_equal 1, status.exitstatus, output
      assert_includes output, "Missing DISCORD_BOT_TOKEN"
      assert_not_includes output, "Started Scheduler"
      assert_includes output, "Shutdown Supervisor(async)"
      assert_includes output, "- Goodbye!"
      assert_no_queue_processes(env)
    end
  end

  test "combined Puma in async mode drains Solid Queue and exits one on a fatal Discord polling error" do
    with_scheduler_database do |env, dir|
      env["SOLID_QUEUE_SUPERVISOR_MODE"] = "async"
      env["DISCORD_BOT_TOKEN"] = "test"
      output, status = Open3.capture2e(env, "timeout", "-k", "3", "15", *puma_command(dir))

      assert_equal 1, status.exitstatus, output
      assert_match(/(?:no such table|Could not find table).*trigger_cursors/i, output)
      assert_includes output, "Shutdown Scheduler"
      assert_includes output, "Shutdown Supervisor(async)"
      assert_includes output, "- Goodbye!"
      assert_no_queue_processes(env)
    end
  end

  test "combined Puma in async mode shuts down normally on interrupt" do
    with_scheduler_database(broken_cursor: false) do |env, dir|
      env["SOLID_QUEUE_SUPERVISOR_MODE"] = "async"
      env["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows/test_workflow").to_s

      Open3.popen2e(env, *puma_command(dir), pgroup: true) do |input, stream, child|
        input.close
        output = +""
        Timeout.timeout(15) do
          stream.each_line do |line|
            output << line
            break if line.include?("Started Scheduler")
          end
          Process.kill(:INT, child.pid) if child.alive?
          output << stream.read
          status = child.value

          assert_predicate status, :success?, output
          assert_includes output, "Started Supervisor(async)"
          assert_includes output, "Shutdown Scheduler"
          assert_includes output, "Shutdown Supervisor(async)"
        end
      ensure
        Process.kill(:KILL, -child.pid) if child.alive?
      end

      assert_no_queue_processes(env)
    end
  end

  private

  def with_scheduler_database(broken_cursor: true)
    Dir.mktmpdir do |dir|
      env = {
        "RAILS_ENV"                      => "production",
        "RAILS_LOG_LEVEL"                => "info",
        "SECRET_KEY_BASE"                => "scheduler-test-secret",
        "R3X_SKIP_VAULT_ENV_LOAD"        => "true",
        "R3X_WORKFLOW_PATHS"             => Rails.root.join("test/fixtures/discord_polling").to_s,
        "DATABASE_URL"                   => nil,
        "R3X_DATABASE_URL"               => nil,
        "R3X_DATABASE_PATH"              => File.join(dir, "scheduler.sqlite3"),
        "R3X_DISCORD_ALLOWED_AUTHOR_IDS" => "1",
        "DISCORD_BOT_TOKEN"              => nil,
        "SOLID_QUEUE_CONFIG"             => nil,
        "SOLID_QUEUE_IN_PUMA"            => "true",
        "SOLID_QUEUE_ONLY_RECURRING"     => nil,
        "SOLID_QUEUE_SKIP_RECURRING"     => nil,
        "SOLID_QUEUE_SUPERVISOR_MODE"    => nil,
        "WEB_CONCURRENCY"                => "0",
      }
      prepare_database = 'load Rails.root.join("db/schema.rb")'
      prepare_database += "; ActiveRecord::Base.connection.drop_table(:trigger_cursors)" if broken_cursor
      output, status = Open3.capture2e(env, "bin/rails", "runner", prepare_database)

      assert_predicate status, :success?, output
      yield env, dir
    end
  end

  def puma_command(dir)
    ["bin/rails", "server", "-b", "127.0.0.1", "-p", "0", "-P", File.join(dir, "puma.pid")]
  end

  def assert_no_queue_processes(env)
    SQLite3::Database.new(env.fetch("R3X_DATABASE_PATH"), readonly: true) do |database|
      assert_empty database.execute("SELECT * FROM solid_queue_processes")
    end
  end

  def assert_discord_scheduler_failures(env, *command)
    output, status = Open3.capture2e(env, "timeout", "-k", "3", "15", *command)

    assert_equal 1, status.exitstatus, output
    assert_includes output, "Missing DISCORD_BOT_TOKEN"

    output, status = Open3.capture2e(env.merge("DISCORD_BOT_TOKEN" => "test"), "timeout", "-k", "3", "15", *command)

    assert_equal 1, status.exitstatus, output
    assert_includes output, "Fatal Discord polling error"
    assert_match(/(?:no such table|Could not find table).*trigger_cursors/i, output)
  end
end

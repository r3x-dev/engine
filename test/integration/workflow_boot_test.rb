require "test_helper"
require "fileutils"
require "shellwords"
require "securerandom"

class WorkflowBootTest < ActiveSupport::TestCase
  setup do
    @fixture_path = "test/fixtures/workflows/test_workflow/workflow.rb".freeze
  end

  test "run command ignores unrelated workflow packs" do
    Dir.mktmpdir do |dir|
      broken_dir = File.join(dir, "broken_workflow")
      FileUtils.mkdir_p(broken_dir)
      File.write(File.join(broken_dir, "workflow.rb"), <<~RUBY)
        module Workflows
          class BrokenWorkflow < R3x::Workflow::Base
            def run(ctx)
              { secret: ENV["NOPE"] }
            end
          end
        end
      RUBY

      workflow_paths = [ broken_dir, Rails.root.join("test/fixtures/workflows").to_s ].join(File::PATH_SEPARATOR)

      output = run_command(
        "bundle exec ruby bin/workflow run #{@fixture_path} 2>&1",
        env: { "R3X_WORKFLOW_PATHS" => workflow_paths }
      )

      assert $?.success?, "CLI command failed: #{output}"
      assert_includes output, "Running: #{@fixture_path}"
      assert_includes output, "Test workflow executed successfully"
    end
  end

  test "server hook loads workflows but does not schedule them when solid queue is out of process" do
    script_path = Rails.root.join("tmp/server_hook_test_#{SecureRandom.hex(4)}.rb")
    idle_marker_path = Rails.root.join("tmp/server_idle_#{SecureRandom.hex(4)}.txt")
    load_marker_path = Rails.root.join("tmp/server_load_#{SecureRandom.hex(4)}.txt")
    unexpected_schedule_marker_path = Rails.root.join("tmp/server_unexpected_schedule_#{SecureRandom.hex(4)}.txt")
    FileUtils.mkdir_p(script_path.dirname)
    File.write(script_path, <<~RUBY)
      require_relative "../config/environment"

      module R3x
        module Workflow
          module Boot
            class << self
              def load_and_schedule!(*args, **kwargs)
                File.write(#{unexpected_schedule_marker_path.to_s.inspect}, "1")
              end

              def load!(*args, **kwargs)
                File.write(#{load_marker_path.to_s.inspect}, "1")
              end
            end
          end
        end
      end

      Rails.application.load_server
      File.write(#{idle_marker_path.to_s.inspect}, "1")
    RUBY

    command_output = run_command(
      "bundle exec ruby #{Shellwords.escape(script_path.to_s)} 2>&1",
      env: { "RAILS_ENV" => "production", "SOLID_QUEUE_IN_PUMA" => nil }
    )

    assert $?.success?, "server hook command failed: #{command_output}"
    assert File.exist?(idle_marker_path), "expected server hook script to finish: #{command_output}"
    assert File.exist?(load_marker_path), "expected server hook to call load!: #{command_output}"
    refute File.exist?(unexpected_schedule_marker_path), "expected server hook not to call load_and_schedule!: #{command_output}"
  ensure
    FileUtils.rm_f(script_path) if script_path
    FileUtils.rm_f(idle_marker_path) if idle_marker_path
    FileUtils.rm_f(load_marker_path) if load_marker_path
    FileUtils.rm_f(unexpected_schedule_marker_path) if unexpected_schedule_marker_path
  end

  test "server hook loads and schedules workflows when solid queue runs in puma" do
    script_path = Rails.root.join("tmp/server_hook_test_#{SecureRandom.hex(4)}.rb")
    schedule_marker_path = Rails.root.join("tmp/server_schedule_#{SecureRandom.hex(4)}.txt")
    FileUtils.mkdir_p(script_path.dirname)
    File.write(script_path, <<~RUBY)
      require_relative "../config/environment"

      module R3x
        module Workflow
          module Boot
            class << self
              def load_and_schedule!(*args, **kwargs)
                File.write(#{schedule_marker_path.to_s.inspect}, "1")
              end
            end
          end
        end
      end

      Rails.application.load_server
    RUBY

    command_output = run_command(
      "bundle exec ruby #{Shellwords.escape(script_path.to_s)} 2>&1",
      env: { "RAILS_ENV" => "production", "SOLID_QUEUE_IN_PUMA" => "true" }
    )

    assert $?.success?, "server hook command failed: #{command_output}"
    assert File.exist?(schedule_marker_path), "expected server hook to call load_and_schedule!: #{command_output}"
  ensure
    FileUtils.rm_f(script_path) if script_path
    FileUtils.rm_f(schedule_marker_path) if schedule_marker_path
  end

  test "jobs entrypoint loads and schedules workflows before cli starts when solid queue is out of process" do
    script_path = Rails.root.join("tmp/jobs_entrypoint_test_#{SecureRandom.hex(4)}.rb")
    cli_marker_path = Rails.root.join("tmp/jobs_cli_#{SecureRandom.hex(4)}.txt")
    load_marker_path = Rails.root.join("tmp/jobs_load_#{SecureRandom.hex(4)}.txt")
    schedule_marker_path = Rails.root.join("tmp/jobs_schedule_#{SecureRandom.hex(4)}.txt")
    FileUtils.mkdir_p(script_path.dirname)
    File.write(script_path, <<~RUBY)
      require_relative "../config/environment"
      require "solid_queue/cli"

      module R3x
        module Workflow
          module Boot
            class << self
              def load!(*args, **kwargs)
                File.write(#{load_marker_path.to_s.inspect}, "1")
              end

              def load_and_schedule!(*args, **kwargs)
                File.write(#{schedule_marker_path.to_s.inspect}, "1")
              end
            end
          end
        end
      end

      class SolidQueue::Cli
        def self.start(*)
          File.write(#{cli_marker_path.to_s.inspect}, "1")
        end
      end

      load "bin/jobs"
    RUBY

    command_output = run_command(
      "bundle exec ruby #{Shellwords.escape(script_path.to_s)} 2>&1",
      env: { "RAILS_ENV" => "production", "SOLID_QUEUE_IN_PUMA" => nil }
    )

    assert $?.success?, "jobs command failed: #{command_output}"
    assert File.exist?(cli_marker_path), "expected jobs entrypoint to start cli: #{command_output}"
    refute File.exist?(load_marker_path), "expected jobs entrypoint not to call load! directly: #{command_output}"
    assert File.exist?(schedule_marker_path), "expected jobs entrypoint to call load_and_schedule!: #{command_output}"
  ensure
    FileUtils.rm_f(script_path) if script_path
    FileUtils.rm_f(cli_marker_path) if cli_marker_path
    FileUtils.rm_f(load_marker_path) if load_marker_path
    FileUtils.rm_f(schedule_marker_path) if schedule_marker_path
  end

  test "jobs entrypoint only loads workflows when solid queue runs in puma" do
    script_path = Rails.root.join("tmp/jobs_entrypoint_test_#{SecureRandom.hex(4)}.rb")
    cli_marker_path = Rails.root.join("tmp/jobs_cli_#{SecureRandom.hex(4)}.txt")
    load_marker_path = Rails.root.join("tmp/jobs_load_#{SecureRandom.hex(4)}.txt")
    schedule_marker_path = Rails.root.join("tmp/jobs_schedule_#{SecureRandom.hex(4)}.txt")
    FileUtils.mkdir_p(script_path.dirname)
    File.write(script_path, <<~RUBY)
      require_relative "../config/environment"
      require "solid_queue/cli"

      module R3x
        module Workflow
          module Boot
            class << self
              def load!(*args, **kwargs)
                File.write(#{load_marker_path.to_s.inspect}, "1")
              end

              def load_and_schedule!(*args, **kwargs)
                File.write(#{schedule_marker_path.to_s.inspect}, "1")
              end
            end
          end
        end
      end

      class SolidQueue::Cli
        def self.start(*)
          File.write(#{cli_marker_path.to_s.inspect}, "1")
        end
      end

      load "bin/jobs"
    RUBY

    command_output = run_command(
      "bundle exec ruby #{Shellwords.escape(script_path.to_s)} 2>&1",
      env: { "RAILS_ENV" => "production", "SOLID_QUEUE_IN_PUMA" => "true" }
    )

    assert $?.success?, "jobs command failed: #{command_output}"
    assert File.exist?(cli_marker_path), "expected jobs entrypoint to start cli: #{command_output}"
    assert File.exist?(load_marker_path), "expected jobs entrypoint to call load!: #{command_output}"
    refute File.exist?(schedule_marker_path), "expected jobs entrypoint not to call load_and_schedule!: #{command_output}"
  ensure
    FileUtils.rm_f(script_path) if script_path
    FileUtils.rm_f(cli_marker_path) if cli_marker_path
    FileUtils.rm_f(load_marker_path) if load_marker_path
    FileUtils.rm_f(schedule_marker_path) if schedule_marker_path
  end

  test "jobs-worker entrypoint only loads workflows and sets worker defaults" do
    script_path = Rails.root.join("tmp/jobs_worker_entrypoint_test_#{SecureRandom.hex(4)}.rb")
    cli_marker_path = Rails.root.join("tmp/jobs_worker_cli_#{SecureRandom.hex(4)}.txt")
    load_marker_path = Rails.root.join("tmp/jobs_worker_load_#{SecureRandom.hex(4)}.txt")
    schedule_marker_path = Rails.root.join("tmp/jobs_worker_schedule_#{SecureRandom.hex(4)}.txt")
    config_marker_path = Rails.root.join("tmp/jobs_worker_config_#{SecureRandom.hex(4)}.txt")
    skip_recurring_marker_path = Rails.root.join("tmp/jobs_worker_skip_#{SecureRandom.hex(4)}.txt")
    FileUtils.mkdir_p(script_path.dirname)
    File.write(script_path, <<~RUBY)
      require_relative "../config/environment"
      require "solid_queue/cli"

      module R3x
        module Workflow
          module Boot
            class << self
              def load!(*args, **kwargs)
                File.write(#{load_marker_path.to_s.inspect}, "1")
              end

              def load_and_schedule!(*args, **kwargs)
                File.write(#{schedule_marker_path.to_s.inspect}, "1")
              end
            end
          end
        end
      end

      class SolidQueue::Cli
        def self.start(*)
          File.write(#{cli_marker_path.to_s.inspect}, "1")
          File.write(#{config_marker_path.to_s.inspect}, ENV["SOLID_QUEUE_CONFIG"].to_s)
          File.write(#{skip_recurring_marker_path.to_s.inspect}, ENV["SOLID_QUEUE_SKIP_RECURRING"].to_s)
        end
      end

      load "bin/jobs-worker"
    RUBY

    command_output = run_command(
      "bundle exec ruby #{Shellwords.escape(script_path.to_s)} 2>&1",
      env: { "RAILS_ENV" => "production", "SOLID_QUEUE_IN_PUMA" => nil }
    )

    assert $?.success?, "jobs-worker command failed: #{command_output}"
    assert File.exist?(cli_marker_path), "expected jobs-worker entrypoint to start cli: #{command_output}"
    assert File.exist?(load_marker_path), "expected jobs-worker entrypoint to call load!: #{command_output}"
    refute File.exist?(schedule_marker_path), "expected jobs-worker entrypoint not to call load_and_schedule!: #{command_output}"
    assert_equal "config/queue.worker.yml", File.read(config_marker_path)
    assert_equal "true", File.read(skip_recurring_marker_path)
  ensure
    FileUtils.rm_f(script_path) if script_path
    FileUtils.rm_f(cli_marker_path) if cli_marker_path
    FileUtils.rm_f(load_marker_path) if load_marker_path
    FileUtils.rm_f(schedule_marker_path) if schedule_marker_path
    FileUtils.rm_f(config_marker_path) if config_marker_path
    FileUtils.rm_f(skip_recurring_marker_path) if skip_recurring_marker_path
  end

  test "jobs-scheduler entrypoint schedules workflows and sets scheduler defaults" do
    script_path = Rails.root.join("tmp/jobs_scheduler_entrypoint_test_#{SecureRandom.hex(4)}.rb")
    cli_marker_path = Rails.root.join("tmp/jobs_scheduler_cli_#{SecureRandom.hex(4)}.txt")
    load_marker_path = Rails.root.join("tmp/jobs_scheduler_load_#{SecureRandom.hex(4)}.txt")
    schedule_marker_path = Rails.root.join("tmp/jobs_scheduler_schedule_#{SecureRandom.hex(4)}.txt")
    config_marker_path = Rails.root.join("tmp/jobs_scheduler_config_#{SecureRandom.hex(4)}.txt")
    FileUtils.mkdir_p(script_path.dirname)
    File.write(script_path, <<~RUBY)
      require_relative "../config/environment"
      require "solid_queue/cli"

      module R3x
        module Workflow
          module Boot
            class << self
              def load!(*args, **kwargs)
                File.write(#{load_marker_path.to_s.inspect}, "1")
              end

              def load_and_schedule!(*args, **kwargs)
                File.write(#{schedule_marker_path.to_s.inspect}, "1")
              end
            end
          end
        end
      end

      class SolidQueue::Cli
        def self.start(*)
          File.write(#{cli_marker_path.to_s.inspect}, "1")
          File.write(#{config_marker_path.to_s.inspect}, ENV["SOLID_QUEUE_CONFIG"].to_s)
        end
      end

      load "bin/jobs-scheduler"
    RUBY

    command_output = run_command(
      "bundle exec ruby #{Shellwords.escape(script_path.to_s)} 2>&1",
      env: { "RAILS_ENV" => "production", "SOLID_QUEUE_IN_PUMA" => nil }
    )

    assert $?.success?, "jobs-scheduler command failed: #{command_output}"
    assert File.exist?(cli_marker_path), "expected jobs-scheduler entrypoint to start cli: #{command_output}"
    refute File.exist?(load_marker_path), "expected jobs-scheduler entrypoint not to call load! directly: #{command_output}"
    assert File.exist?(schedule_marker_path), "expected jobs-scheduler entrypoint to call load_and_schedule!: #{command_output}"
    assert_equal "config/queue.scheduler.yml", File.read(config_marker_path)
  ensure
    FileUtils.rm_f(script_path) if script_path
    FileUtils.rm_f(cli_marker_path) if cli_marker_path
    FileUtils.rm_f(load_marker_path) if load_marker_path
    FileUtils.rm_f(schedule_marker_path) if schedule_marker_path
    FileUtils.rm_f(config_marker_path) if config_marker_path
  end

  test "jobs-worker entrypoint keeps explicit solid queue config override" do
    script_path = Rails.root.join("tmp/jobs_entrypoint_test_#{SecureRandom.hex(4)}.rb")
    config_marker_path = Rails.root.join("tmp/jobs_config_#{SecureRandom.hex(4)}.txt")
    FileUtils.mkdir_p(script_path.dirname)
    File.write(script_path, <<~RUBY)
      require_relative "../config/environment"
      require "solid_queue/cli"

      class SolidQueue::Cli
        def self.start(*)
          File.write(#{config_marker_path.to_s.inspect}, ENV["SOLID_QUEUE_CONFIG"].to_s)
        end
      end

      load "bin/jobs-worker"
    RUBY

    command_output = run_command(
      "bundle exec ruby #{Shellwords.escape(script_path.to_s)} 2>&1",
      env: {
        "RAILS_ENV" => "production",
        "SOLID_QUEUE_CONFIG" => "config/custom.yml",
        "SOLID_QUEUE_IN_PUMA" => nil
      }
    )

    assert $?.success?, "jobs command failed: #{command_output}"
    assert_equal "config/custom.yml", File.read(config_marker_path)
  ensure
    FileUtils.rm_f(script_path) if script_path
    FileUtils.rm_f(config_marker_path) if config_marker_path
  end

  test "jobs-worker entrypoint keeps explicit skip recurring override" do
    script_path = Rails.root.join("tmp/jobs_entrypoint_test_#{SecureRandom.hex(4)}.rb")
    skip_recurring_marker_path = Rails.root.join("tmp/jobs_skip_recurring_#{SecureRandom.hex(4)}.txt")
    FileUtils.mkdir_p(script_path.dirname)
    File.write(script_path, <<~RUBY)
      require_relative "../config/environment"
      require "solid_queue/cli"

      class SolidQueue::Cli
        def self.start(*)
          File.write(#{skip_recurring_marker_path.to_s.inspect}, ENV["SOLID_QUEUE_SKIP_RECURRING"].to_s)
        end
      end

      load "bin/jobs-worker"
    RUBY

    command_output = run_command(
      "bundle exec ruby #{Shellwords.escape(script_path.to_s)} 2>&1",
      env: {
        "RAILS_ENV" => "production",
        "SOLID_QUEUE_SKIP_RECURRING" => "false",
        "SOLID_QUEUE_IN_PUMA" => nil
      }
    )

    assert $?.success?, "jobs command failed: #{command_output}"
    assert_equal "false", File.read(skip_recurring_marker_path)
  ensure
    FileUtils.rm_f(script_path) if script_path
    FileUtils.rm_f(skip_recurring_marker_path) if skip_recurring_marker_path
  end

  test "docker entrypoint fails fast for production runtime commands without secret key base" do
    command_output = run_command(
      "bin/docker-entrypoint ./bin/jobs-worker 2>&1",
      env: { "RAILS_ENV" => "production" },
      inject_production_secret: false
    )

    refute $?.success?, "docker entrypoint unexpectedly succeeded: #{command_output}"
    assert_includes command_output, "Missing SECRET_KEY_BASE for production runtime"
  end

  test "docker entrypoint allows non-runtime production commands without secret key base" do
    command_output = run_command(
      "bin/docker-entrypoint ruby -e 'exit 0' 2>&1",
      env: { "RAILS_ENV" => "production" },
      inject_production_secret: false
    )

    assert $?.success?, "docker entrypoint command failed: #{command_output}"
  end

  private

  def run_command(command, env: {}, inject_production_secret: true)
    if inject_production_secret && env["RAILS_ENV"] == "production"
      env = { "SECRET_KEY_BASE" => "workflow-boot-test-secret" }.merge(env.compact)
    else
      env = env.compact
    end

    env_string = env.map { |key, value| "#{key}=#{Shellwords.escape(value)}" }.join(" ")
    full_command = [ env_string, command ].reject(&:blank?).join(" ")

    `#{full_command}`
  end
end

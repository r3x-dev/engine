require "test_helper"

module R3x
  module Workflow
    class EntrypointTest < ActiveSupport::TestCase
      test "server boot action schedules in development by default" do
        assert_equal :load_and_schedule, Entrypoint.server_boot_action(rails_env: "development")
      end

      test "server boot action schedules when solid queue runs in puma" do
        assert_equal :load_and_schedule, Entrypoint.server_boot_action(rails_env: "production", solid_queue_in_puma: "true")
      end

      test "server boot action only loads workflows for out of process production jobs" do
        assert_equal :load, Entrypoint.server_boot_action(rails_env: "production", solid_queue_in_puma: nil)
      end

      test "jobs boot action schedules when solid queue is out of process" do
        assert_equal :load_and_schedule, Entrypoint.jobs_boot_action(solid_queue_in_puma: nil)
      end

      test "jobs boot action only loads workflows when solid queue runs in puma" do
        assert_equal :load, Entrypoint.jobs_boot_action(solid_queue_in_puma: "true")
      end

      test "boot_server dispatches the selected boot action" do
        calls = []
        boot = build_boot_double(calls)

        Entrypoint.boot_server!(rails_env: "production", solid_queue_in_puma: nil, boot: boot)
        Entrypoint.boot_server!(rails_env: "production", solid_queue_in_puma: "true", boot: boot)

        assert_equal [ :load, :load_and_schedule ], calls
      end

      test "start_jobs dispatches boot before starting the cli" do
        calls = []
        boot = build_boot_double(calls)
        cli = build_cli_double(calls)

        Entrypoint.start_jobs!(argv: [ "--skip-daemon" ], env: {}, boot: boot, cli: cli)
        Entrypoint.start_jobs!(argv: [ "--skip-daemon" ], env: { "SOLID_QUEUE_IN_PUMA" => "true" }, boot: boot, cli: cli)

        assert_equal [
          :load_and_schedule,
          [ :cli, [ "--skip-daemon" ] ],
          :load,
          [ :cli, [ "--skip-daemon" ] ]
        ], calls
      end

      test "start_jobs_worker applies defaults, preserves overrides, and starts the cli" do
        calls = []
        boot = build_boot_double(calls)
        cli = build_cli_double(calls)

        default_env = {}
        Entrypoint.start_jobs_worker!(argv: [ "--skip-daemon" ], env: default_env, boot: boot, cli: cli)

        assert_equal "config/queue.worker.yml", default_env["SOLID_QUEUE_CONFIG"]
        assert_equal "true", default_env["SOLID_QUEUE_SKIP_RECURRING"]

        override_env = {
          "SOLID_QUEUE_CONFIG" => "config/custom.yml",
          "SOLID_QUEUE_SKIP_RECURRING" => "false"
        }
        Entrypoint.start_jobs_worker!(argv: [ "--skip-daemon" ], env: override_env, boot: boot, cli: cli)

        assert_equal "config/custom.yml", override_env["SOLID_QUEUE_CONFIG"]
        assert_equal "false", override_env["SOLID_QUEUE_SKIP_RECURRING"]
        assert_equal [
          :load,
          [ :cli, [ "--skip-daemon" ] ],
          :load,
          [ :cli, [ "--skip-daemon" ] ]
        ], calls
      end

      test "start_jobs_scheduler applies defaults, preserves overrides, and starts the cli" do
        calls = []
        boot = build_boot_double(calls)
        cli = build_cli_double(calls)

        default_env = {}
        Entrypoint.start_jobs_scheduler!(argv: [ "--skip-daemon" ], env: default_env, boot: boot, cli: cli)

        assert_equal "config/queue.scheduler.yml", default_env["SOLID_QUEUE_CONFIG"]

        override_env = { "SOLID_QUEUE_CONFIG" => "config/custom.yml" }
        Entrypoint.start_jobs_scheduler!(argv: [ "--skip-daemon" ], env: override_env, boot: boot, cli: cli)

        assert_equal "config/custom.yml", override_env["SOLID_QUEUE_CONFIG"]
        assert_equal [
          :load_and_schedule,
          [ :cli, [ "--skip-daemon" ] ],
          :load_and_schedule,
          [ :cli, [ "--skip-daemon" ] ]
        ], calls
      end

      private

      def build_boot_double(calls)
        Module.new do
          define_singleton_method(:load!) { calls << :load }
          define_singleton_method(:load_and_schedule!) { calls << :load_and_schedule }
        end
      end

      def build_cli_double(calls)
        Class.new do
          define_singleton_method(:start) do |argv|
            calls << [ :cli, argv ]
          end
        end
      end
    end
  end
end

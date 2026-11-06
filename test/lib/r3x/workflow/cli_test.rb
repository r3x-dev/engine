# frozen_string_literal: true

require "test_helper"
require "fileutils"

module R3x
  module Workflow
    class CliTest < ActiveSupport::TestCase
      setup do
        @fixture_dir = Rails.root.join("test/fixtures/workflows")
        @fixture_path = @fixture_dir.join("test_workflow/workflow.rb")
        @continuable_fixture_path = @fixture_dir.join("continuable_workflow/workflow.rb")
        @original_run_env = %w[R3X_DRY_RUN R3X_SKIP_CACHE].to_h { |key| [key, ENV.delete(key)] }
        @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
        ENV["R3X_WORKFLOW_PATHS"] = @fixture_dir.to_s
        R3x::Workflow::PackLoader.load!(rebuild_registry: true)
        Workflows::ContinuableWorkflow.reset_events!
      end

      teardown do
        ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
        @original_run_env.each { |key, value| ENV[key] = value }
        R3x::Workflow::Registry.reset!
      end

      test "list prints workflows from the registry" do
        output = StringIO.new

        Cli.new(stdout: output).list

        assert_includes output.string, "Available workflows:"
        assert_includes output.string, "test_workflow"
        assert_includes output.string, "schedule"
      end

      test "list prints empty state when no workflows are registered" do
        output = StringIO.new
        pack_loader = Module.new do
          def self.load!
          end
        end
        registry = Module.new do
          def self.all = []
        end

        Cli.new(stdout: output, pack_loader:, registry:).list

        assert_equal "No workflows found.\n", output.string
      end

      test "info prints workflow details" do
        output = StringIO.new

        Cli.new(stdout: output).info("test_workflow")

        assert_includes output.string, "Workflow: test_workflow"
        assert_includes output.string, "Workflows::TestWorkflow"
        assert_includes output.string, "schedule"
      end

      test "run executes workflow from a file path" do
        output = StringIO.new

        result = Cli.new(stdout: output).run(@fixture_path.to_s)

        assert_includes output.string, "Running with dry run by default: #{@fixture_path}"
        assert_equal({ "test" => true, "message" => "Test workflow executed successfully" }, result)
      end

      test "run resumes continuable workflows until completion" do
        output = StringIO.new
        cli = Cli.new(stdout: output)
        cli.stubs(:sleep)

        result = cli.run(@continuable_fixture_path.to_s)

        assert_equal %w[first second third complete], Workflows::ContinuableWorkflow.events
        assert_equal({ "events" => %w[first second third] }, result)
      end

      test "run waits between continuable workflow resumptions by default" do
        output = StringIO.new
        cli = Cli.new(stdout: output)
        cli.expects(:sleep).twice.with(2.minutes.to_i)

        cli.run(@continuable_fixture_path.to_s)
      end

      test "run supports polynomial wait between continuable workflow resumptions" do
        original_resume_options = Workflows::ContinuableWorkflow.resume_options
        Workflows::ContinuableWorkflow.resume_options = { wait: :polynomially_longer }
        output = StringIO.new
        cli = Cli.new(stdout: output)
        sleeps = sequence("sleeps")
        cli.expects(:sleep).with(3).in_sequence(sleeps)
        cli.expects(:sleep).with(18).in_sequence(sleeps)

        cli.run(@continuable_fixture_path.to_s)
      ensure
        Workflows::ContinuableWorkflow.resume_options = original_resume_options
      end

      test "run supports wait until between continuable workflow resumptions" do
        original_resume_options = Workflows::ContinuableWorkflow.resume_options
        travel_to Time.zone.local(2026, 1, 1, 12) do
          Workflows::ContinuableWorkflow.resume_options = { wait_until: 30.seconds.from_now }
          output = StringIO.new
          cli = Cli.new(stdout: output)
          cli.expects(:sleep).twice.with(30.0)

          cli.run(@continuable_fixture_path.to_s)
        end
      ensure
        Workflows::ContinuableWorkflow.resume_options = original_resume_options
      end

      test "run can skip waiting between continuable workflow resumptions" do
        output = StringIO.new
        cli = Cli.new(stdout: output)
        cli.expects(:sleep).never

        cli.run(@continuable_fixture_path.to_s, wait: false)
      end

      test "run supports dry run and skip cache messaging without leaking env overrides" do
        output = StringIO.new

        Cli.new(stdout: output).run(@fixture_path.to_s, dry_run: true, skip_cache: true)

        assert_includes output.string, "Running with dry run + skip cache: #{@fixture_path}"
        assert_includes output.string, "INFO: Global dry run enabled."
        assert_nil ENV["R3X_DRY_RUN"]
        assert_nil ENV["R3X_SKIP_CACHE"]
      end

      test "CLI and ENV global dry run block writes across resumptions and restore the original mode" do
        delivery = stub_request(:post, "https://discord.test/webhook?wait=true")
          .to_return(status: 200, body: '{"id":"123"}', headers: { "Content-Type" => "application/json" })
        acknowledgment = stub_request(:put, "https://miniflux.test/v1/entries").to_return(status: 204)
        reads = stub_request(:get, %r{https://miniflux.test/v1/entries\?})
          .to_return(status: 200, body: '{"entries":[]}', headers: { "Content-Type" => "application/json" })
        path = @fixture_dir.join("dry_run_workflow/workflow.rb").to_s
        output = StringIO.new
        cli = Cli.new(stdout: output)

        with_delivery_env(
          "R3X_DRY_RUN"          => "false",
          "R3X_DISCORD_DRY_RUN"  => "false",
          "R3X_MINIFLUX_DRY_RUN" => "false",
        ) do
          result = cli.run(path, dry_run: true, wait: false)

          assert_not_requested delivery
          assert_not_requested acknowledgment
          assert_requested reads, times: 1
          assert result.fetch("explicit_dry_run")
          assert result.fetch("thread_dry_run")
          assert_includes output.string, "INFO: Global dry run enabled. Ignored real-write overrides: R3X_DISCORD_DRY_RUN, R3X_MINIFLUX_DRY_RUN."
          assert_equal "false", ENV["R3X_DRY_RUN"]
          assert_equal "false", ENV["R3X_DISCORD_DRY_RUN"]
          assert_equal "false", ENV["R3X_MINIFLUX_DRY_RUN"]

          ENV["R3X_DRY_RUN"] = "true"
          result = cli.run(path, wait: false)

          assert_not_requested delivery
          assert_not_requested acknowledgment
          assert_requested reads, times: 2
          assert result.fetch("explicit_dry_run")
          assert result.fetch("thread_dry_run")

          ENV["R3X_DRY_RUN"] = "false"
          output.truncate(0)
          output.rewind
          result = cli.run(path, wait: false)

          assert_requested delivery, times: 1
          assert_requested acknowledgment, times: 1
          assert_requested reads, times: 3
          assert_not result.fetch("explicit_dry_run")
          assert_not result.fetch("thread_dry_run")
          assert_includes output.string, "INFO: Default: real writes."
        end
      end

      test "run restores policy after a resumed workflow raises" do
        stub_request(:get, %r{https://miniflux.test/v1/entries\?}).to_return(status: 500)
        path = @fixture_dir.join("dry_run_workflow/workflow.rb").to_s

        with_delivery_env("R3X_DRY_RUN" => "false", "R3X_DISCORD_DRY_RUN" => "false", "R3X_MINIFLUX_DRY_RUN" => "false") do
          assert_raises(HTTPX::HTTPError) do
            Cli.new(stdout: StringIO.new).run(path, dry_run: true, skip_cache: true, wait: false)
          end

          assert_not R3x::Policy.dry_run_for(:discord)
          assert_equal "false", ENV["R3X_DRY_RUN"]
          assert_nil ENV["R3X_SKIP_CACHE"]
        end
      end

      test "explicit real mode preserves per-feature dry run" do
        acknowledgment = stub_request(:put, "https://miniflux.test/v1/entries").to_return(status: 204)
        stub_request(:get, %r{https://miniflux.test/v1/entries\?})
          .to_return(status: 200, body: '{"entries":[]}', headers: { "Content-Type" => "application/json" })
        path = @fixture_dir.join("dry_run_workflow/workflow.rb").to_s
        output = StringIO.new

        with_delivery_env("R3X_DRY_RUN" => "true", "R3X_DISCORD_DRY_RUN" => "true", "R3X_MINIFLUX_DRY_RUN" => nil) do
          Cli.new(stdout: output).run(path, dry_run: false, wait: false)

          assert_not_requested :post, "https://discord.test/webhook?wait=true"
          assert_requested acknowledgment, times: 1
          assert_includes output.string, "INFO: Default: real writes. Configured dry-run overrides: R3X_DISCORD_DRY_RUN."
          assert_equal "true", ENV["R3X_DRY_RUN"]
        end
      end

      test "explicit dry run still rejects invalid per-feature flags before executing" do
        with_env("R3X_DISCORD_DRY_RUN" => "maybe") do
          error = assert_raises(ArgumentError) do
            Cli.new(stdout: StringIO.new).run(@fixture_path.to_s, dry_run: true)
          end

          assert_equal 'Invalid boolean for R3X_DISCORD_DRY_RUN: "maybe"', error.message
        end
      end

      test "run supports explicit skip cache override in production" do
        output = StringIO.new
        Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

        Cli.new(stdout: output).run(@fixture_path.to_s, skip_cache: true)

        assert_includes output.string, "Running with skip cache: #{@fixture_path}"
        assert_nil ENV["R3X_SKIP_CACHE"]
      end

      test "run accepts absolute paths" do
        output = StringIO.new

        Cli.new(stdout: output).run(@fixture_path.expand_path.to_s)

        assert_includes output.string, "Running with dry run by default: #{@fixture_path.expand_path}"
      end

      test "run with --no-dry-run disables dry run even in test environment" do
        output = StringIO.new

        Cli.new(stdout: output).run(@fixture_path.to_s, dry_run: false)

        assert_includes output.string, "Running: #{@fixture_path}"
      end

      test "run ignores unrelated workflow packs when executing a direct file path" do
        Dir.mktmpdir do |dir|
          broken_dir = File.join(dir, "broken_workflow")
          FileUtils.mkdir_p(broken_dir)
          File.write(File.join(broken_dir, "workflow.rb"), <<~RUBY)
            module Workflows
              class BrokenWorkflow < R3x::Workflow::Base
                def run
                  { secret: ENV.fetch("NOPE") }
                end
              end
            end
          RUBY

          ENV["R3X_WORKFLOW_PATHS"] = [broken_dir, @fixture_dir.to_s].join(File::PATH_SEPARATOR)
          output = StringIO.new

          Cli.new(stdout: output).run(@fixture_path.to_s)

          assert_includes output.string, "Running with dry run by default: #{@fixture_path}"
        end
      end

      test "run raises for a missing file" do
        error = assert_raises(ArgumentError) do
          Cli.new(stdout: StringIO.new).run("/nonexistent/path.rb")
        end

        assert_equal "Workflow file not found: /nonexistent/path.rb", error.message
      end

      test "run raises when given a directory" do
        error = assert_raises(ArgumentError) do
          Cli.new(stdout: StringIO.new).run(@fixture_dir.to_s)
        end

        assert_equal "Not a file: #{@fixture_dir}", error.message
      end

      test "run raises when the file does not define a workflow class" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "workflow.rb")
          File.write(path, "module Workflows; end\n")

          error = assert_raises(ArgumentError) do
            Cli.new(stdout: StringIO.new).run(path)
          end

          assert_equal "No workflow class found in #{path}", error.message
        end
      end

      private

      def with_delivery_env(overrides, &)
        with_env({
          "DISCORD_WEBHOOK_URL" => "https://discord.test/webhook",
          "MINIFLUX_URL"        => "https://miniflux.test",
          "MINIFLUX_API_KEY"    => "test-key",
        }.merge(overrides), &)
      end

      def with_env(values)
        originals = ENV.to_h.slice(*values.keys)
        values.each { |key, value| ENV[key] = value }
        yield
      ensure
        values.each_key { |key| ENV[key] = originals[key] }
      end
    end
  end
end

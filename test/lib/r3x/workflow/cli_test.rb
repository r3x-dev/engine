require "test_helper"
require "fileutils"

module R3x
  module Workflow
    class CliTest < ActiveSupport::TestCase
      setup do
        @fixture_dir = Rails.root.join("test/fixtures/workflows")
        @fixture_path = @fixture_dir.join("test_workflow/workflow.rb")
        @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
        ENV["R3X_WORKFLOW_PATHS"] = @fixture_dir.to_s
        R3x::Workflow::PackLoader.load!(force: true)
      end

      teardown do
        ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
        ENV.delete("R3X_DRY_RUN")
        ENV.delete("R3X_SKIP_CACHE")
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
          def self.load!; end
        end
        registry = Module.new do
          def self.all = []
        end

        Cli.new(stdout: output, pack_loader: pack_loader, registry: registry).list

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

        Cli.new(stdout: output).run(@fixture_path.to_s)

        assert_includes output.string, "Running: #{@fixture_path}"
        assert_includes output.string, "\"test\""
        assert_includes output.string, "Test workflow executed successfully"
      end

      test "run supports dry run and skip cache messaging without leaking env overrides" do
        output = StringIO.new

        Cli.new(stdout: output).run(@fixture_path.to_s, dry_run: true, skip_cache: true)

        assert_includes output.string, "Dry run without cache: #{@fixture_path}"
        assert_nil ENV["R3X_DRY_RUN"]
        assert_nil ENV["R3X_SKIP_CACHE"]
      end

      test "run accepts absolute paths" do
        output = StringIO.new

        Cli.new(stdout: output).run(@fixture_path.expand_path.to_s)

        assert_includes output.string, "Running: #{@fixture_path.expand_path}"
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

          ENV["R3X_WORKFLOW_PATHS"] = [ broken_dir, @fixture_dir.to_s ].join(File::PATH_SEPARATOR)
          output = StringIO.new

          Cli.new(stdout: output).run(@fixture_path.to_s)

          assert_includes output.string, "Running: #{@fixture_path}"
          assert_includes output.string, "Test workflow executed successfully"
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
    end
  end
end

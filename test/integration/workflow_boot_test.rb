require "test_helper"
require "fileutils"
require "shellwords"

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

  test "server hook loads and schedules workflows explicitly" do
    script_path = Rails.root.join("tmp/server_hook_test.rb")
    FileUtils.mkdir_p(script_path.dirname)
    File.write(script_path, <<~RUBY)
      require_relative "../config/environment"

      module R3x
        module Workflow
          module Boot
            class << self
              def load_and_schedule!(*args, **kwargs)
                puts "server-loaded"
              end
            end
          end
        end
      end

      Rails.application.load_server
    RUBY

    output = run_command("bundle exec ruby #{Shellwords.escape(script_path.to_s)} 2>&1")

    assert $?.success?, "server hook command failed: #{output}"
    assert_includes output, "server-loaded"
  ensure
    FileUtils.rm_f(script_path) if script_path
  end

  test "jobs entrypoint loads workflows before cli starts" do
    script_path = Rails.root.join("tmp/jobs_entrypoint_test.rb")
    FileUtils.mkdir_p(script_path.dirname)
    File.write(script_path, <<~RUBY)
      require_relative "../config/environment"
      require "solid_queue/cli"

      module R3x
        module Workflow
          module Boot
            class << self
              def load!(*args, **kwargs)
                File.write("tmp/jobs_pack_loader_called.txt", "1")
              end
            end
          end
        end
      end

      class SolidQueue::Cli
        def self.start(*)
          puts File.exist?("tmp/jobs_pack_loader_called.txt") ? "loaded" : "missing"
        end
      end

      load "bin/jobs"
    RUBY

    output = run_command("bundle exec ruby #{Shellwords.escape(script_path.to_s)} 2>&1")

    assert $?.success?, "jobs command failed: #{output}"
    assert_includes output, "loaded"
  ensure
    FileUtils.rm_f(script_path) if script_path
    FileUtils.rm_f(Rails.root.join("tmp/jobs_pack_loader_called.txt"))
  end

  private

  def run_command(command, env: {})
    env_string = env.map { |key, value| "#{key}=#{Shellwords.escape(value)}" }.join(" ")
    full_command = [ env_string, command ].reject(&:blank?).join(" ")

    `#{full_command}`
  end
end

require "test_helper"
require "shellwords"

class WorkflowCliTest < ActiveSupport::TestCase
  setup do
    @fixture_path = "test/fixtures/workflows/test_workflow/workflow.rb".freeze
  end

  test "list command shows workflows from registry" do
    output = run_cli("list")

    assert_includes output, "test_workflow"
    assert_includes output, "schedule"
  end

  test "run command executes workflow from file path" do
    output = run_cli("run #{@fixture_path}")

    assert_includes output, "Running: #{@fixture_path}"
    assert_includes output, "test"
    assert_includes output, "Test workflow executed successfully"
  end

  test "nonexistent file shows error" do
    output = run_cli("run /nonexistent/path.rb", allow_failure: true)

    assert_includes output, "Workflow file not found"
  end

  test "list command boots through workflow_cli in production-like mode" do
    output = run_cli(
      "list",
      env: {
        "RAILS_ENV" => "production",
        "R3X_SKIP_VAULT_ENV_LOAD" => "true",
        "SECRET_KEY_BASE" => "workflow-cli-production-smoke-secret"
      }
    )

    assert_includes output, "Available workflows:"
    assert_includes output, "test_workflow"
  end

  private

  def run_cli(args, allow_failure: false, env: {})
    env = {
      "R3X_WORKFLOW_PATHS" => Rails.root.join("test/fixtures/workflows").to_s
    }.merge(env)
    env_string = env.map { |key, value| "#{key}=#{Shellwords.escape(value)}" }.join(" ")
    cmd = "#{env_string} bundle exec ruby bin/workflow #{args} 2>&1"
    output = `#{cmd}`

    unless allow_failure
      assert $?.success?, "CLI command failed: #{output}"
    end

    output
  end
end

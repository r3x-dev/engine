# frozen_string_literal: true

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

    assert_includes output, "Running with dry run by default: #{@fixture_path}"
  end

  test "run command accepts skip wait option" do
    output = run_cli("run --skip-wait #{@fixture_path}")

    assert_includes output, "Running with dry run by default: #{@fixture_path}"
  end

  test "run command completes isolated steps with one correlated Active Job identity" do
    output = run_cli("run --skip-wait test/fixtures/workflows/callback_workflow/workflow.rb")
    run_ids = output.scan(/r3x\.run_active_job_id=([^\]\s]+)/).flatten

    assert_includes output, "Resuming workflow"
    assert_includes output, "Workflow run completed"
    assert_not_empty run_ids
    assert_equal 1, run_ids.uniq.size
  end

  test "run command completes a retry on recovery in the foreground" do
    output = run_cli("run --skip-wait test/fixtures/workflows/retry_workflow/workflow.rb")

    assert_includes output, "Workflow run failed"
    assert_includes output, "Workflow run completed"
  end

  test "explicit dry run reports ignored real-write overrides" do
    output = run_cli("run --dry-run #{@fixture_path}", env: { "R3X_DISCORD_DRY_RUN" => "false" })

    assert_includes output, "INFO: Global dry run enabled. Ignored real-write overrides: R3X_DISCORD_DRY_RUN."
    assert_includes output, "Running with dry run: #{@fixture_path}"
  end

  test "global ENV dry run reports ignored real-write overrides" do
    output = run_cli("run #{@fixture_path}", env: { "R3X_DRY_RUN" => "true", "R3X_DISCORD_DRY_RUN" => "false" })

    assert_includes output, "INFO: Global dry run enabled. Ignored real-write overrides: R3X_DISCORD_DRY_RUN."
    assert_includes output, "Running with dry run: #{@fixture_path}"
  end

  test "run warns when ENV enables real writes under the environment dry-run default" do
    output = run_cli("run #{@fixture_path}", env: { "R3X_DRY_RUN" => "", "R3X_DISCORD_DRY_RUN" => "false" })

    assert_includes output, "WARN: Mixed mode. Default: dry run. Configured real-write overrides: R3X_DISCORD_DRY_RUN."
  end

  test "nonexistent file shows error" do
    output = run_cli("run /nonexistent/path.rb", allow_failure: true)

    assert_includes output, "Workflow file not found"
  end

  test "list command boots through workflow_cli in production-like mode" do
    output = run_cli(
      "list",
      env: {
        "RAILS_ENV"               => "production",
        "R3X_SKIP_VAULT_ENV_LOAD" => "true",
        "SECRET_KEY_BASE"         => "workflow-cli-production-smoke-secret",
      },
    )

    assert_includes output, "Available workflows:"
    assert_includes output, "test_workflow"
  end

  private

  def run_cli(args, allow_failure: false, env: {})
    env = {
      "R3X_WORKFLOW_PATHS" => Rails.root.join("test/fixtures/workflows").to_s,
    }.merge(env)
    env_string = env.map { |key, value| "#{key}=#{Shellwords.escape(value)}" }.join(" ")
    cmd = "#{env_string} bundle exec ruby bin/workflow #{args} 2>&1"
    output = `#{cmd}`

    unless allow_failure
      assert_predicate $?, :success?, "CLI command failed: #{output}"
    end

    output
  end
end

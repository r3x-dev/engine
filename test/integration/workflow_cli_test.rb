require "test_helper"

class WorkflowCliTest < ActiveSupport::TestCase
  setup do
    @fixture_path = "test/fixtures/workflows/test_workflow/workflow.rb".freeze
  end

  test "list command shows workflows from registry" do
    output = run_cli("list")

    assert_includes output, "test_workflow"
    assert_includes output, "schedule"
  end

  test "info command shows workflow details" do
    output = run_cli("info test_workflow")

    assert_includes output, "test_workflow"
    assert_includes output, "Workflows::TestWorkflow"
    assert_includes output, "schedule"
  end

  test "run command executes workflow from file path" do
    output = run_cli("run #{@fixture_path}")

    assert_includes output, "Running: #{@fixture_path}"
    assert_includes output, "test"
    assert_includes output, "Test workflow executed successfully"
  end

  test "run command executes workflow from absolute path" do
    abs_path = Rails.root.join(@fixture_path).to_s
    output = run_cli("run #{abs_path}")

    assert_includes output, "Running: #{abs_path}"
    assert_includes output, "test"
  end

  test "run command with dry-run shows file info" do
    output = run_cli("run -d #{@fixture_path}")

    assert_includes output, "Dry run: #{@fixture_path}"
    assert_includes output, "would load from:"
    assert_includes output, "not executing"
  end

  test "run command without arguments shows usage" do
    output = run_cli("run", allow_failure: true)

    assert_includes output, "Usage:"
  end

  test "help command shows commands" do
    output = run_cli("-h")

    assert_includes output, "Commands:"
    assert_includes output, "run"
    assert_includes output, "list"
    assert_includes output, "info"
  end

  test "nonexistent file shows error" do
    output = run_cli("run /nonexistent/path.rb", allow_failure: true)

    assert_includes output, "Workflow file not found"
  end

  test "directory instead of file shows error" do
    output = run_cli("run test/fixtures/workflows", allow_failure: true)

    assert_includes output, "Not a file"
  end

  test "unknown command shows error" do
    output = run_cli("unknown_command", allow_failure: true)

    assert_includes output, "Could not find command"
  end

  private

  def run_cli(args, allow_failure: false)
    cmd = "R3X_WORKFLOW_PATHS='#{Rails.root.join('test/fixtures/workflows')}' bundle exec ruby bin/workflow #{args} 2>&1"
    output = `#{cmd}`

    unless allow_failure
      assert $?.success?, "CLI command failed: #{output}"
    end

    output
  end
end

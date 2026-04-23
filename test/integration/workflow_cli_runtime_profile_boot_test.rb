require "test_helper"
require "multi_json"
require "shellwords"

class WorkflowCliRuntimeProfileBootTest < ActiveSupport::TestCase
  test "production workflow_cli profile boots workflow cli without loading web classes" do
    script = <<~RUBY
      require "multi_json"
      require #{Rails.root.join("config/environment").to_s.inspect}

      R3x::Workflow::Boot.load!

      puts MultiJson.dump(
        runtime_profile: R3x::RuntimeProfile.current,
        workflow_base: defined?(R3x::Workflow::Base),
        workflow_entrypoint: defined?(R3x::Workflow::Entrypoint),
        registered_workflow: R3x::Workflow::Registry.fetch("test_workflow").name,
        routes_reloader_paths: Rails.application.routes_reloader.paths.map(&:to_s),
        mission_control: defined?(MissionControl),
        web_controller: defined?(R3x::WebController),
        dashboard: defined?(R3x::Dashboard),
        workflow_cli: defined?(R3x::Workflow::Cli)
      )
    RUBY

    output = run_command(script)
    payload = MultiJson.load(output.lines.last)

    assert_equal "workflow_cli", payload.fetch("runtime_profile")
    assert_equal "constant", payload.fetch("workflow_base")
    assert_equal "constant", payload.fetch("workflow_entrypoint")
    assert_equal "Workflows::TestWorkflow", payload.fetch("registered_workflow")
    refute_includes payload.fetch("routes_reloader_paths"), Rails.root.join("config/routes.rb").to_s
    assert_nil payload["mission_control"]
    assert_nil payload["web_controller"]
    assert_nil payload["dashboard"]
    assert_equal "constant", payload.fetch("workflow_cli")
  end

  private

  def run_command(script)
    env = {
      "RAILS_ENV" => "production",
      "R3X_RUNTIME_PROFILE" => "workflow_cli",
      "R3X_SKIP_VAULT_ENV_LOAD" => "true",
      "R3X_WORKFLOW_PATHS" => Rails.root.join("test/fixtures/workflows").to_s,
      "SECRET_KEY_BASE" => "workflow-cli-runtime-profile-test-secret"
    }

    env_string = env.map { |key, value| "#{key}=#{Shellwords.escape(value)}" }.join(" ")
    command = %(#{env_string} bundle exec ruby -e #{Shellwords.escape(script)})
    output = `#{command}`

    assert $?.success?, "workflow_cli runtime boot command failed: #{output}"
    output
  end
end

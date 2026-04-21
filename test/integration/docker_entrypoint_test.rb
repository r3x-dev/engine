require "test_helper"
require "shellwords"

class DockerEntrypointTest < ActiveSupport::TestCase
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

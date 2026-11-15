# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"
require "bundler"

class DockerEntrypointCommandTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("r3x entrypoint ")
    FileUtils.mkdir_p(File.join(@directory, "bin"))
    FileUtils.mkdir_p(File.join(@directory, "nested"))
    source = ENV.fetch("DOCKER_ENTRYPOINT_UNDER_TEST", File.expand_path("../../bin/docker-entrypoint", __dir__))
    FileUtils.cp(source, File.join(@directory, "bin/docker-entrypoint"))
    File.write(File.join(@directory, "bin/rails"), <<~SH)
      #!/bin/sh
      printf '%s:%s\n' "$PWD" "$*" >> "$ENTRYPOINT_LOG"
      [ "$1" != db:prepare ] || exit "${PREPARE_EXIT:-0}"
    SH
    FileUtils.chmod(0o755, File.join(@directory, "bin/rails"))
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_runtime_from_subdirectory_prepares_at_app_root_then_keeps_caller_cwd
    output, status = run_entrypoint("../bin/rails", "server")

    assert_predicate status, :success?, output
    assert_equal ["#{@directory}:db:prepare", "#{@directory}/nested:server"], File.readlines(File.join(@directory, "calls"), chomp: true)
  end

  def test_prepare_failure_prevents_runtime_start
    output, status = run_entrypoint("../bin/rails", "server", env: { "PREPARE_EXIT" => "37" })

    assert_equal 37, status.exitstatus, output
    assert_equal ["#{@directory}:db:prepare"], File.readlines(File.join(@directory, "calls"), chomp: true)
  end

  def test_web_startup_from_subdirectory_finds_rails
    FileUtils.cp(File.expand_path("../../bin/web", __dir__), File.join(@directory, "bin/web"))
    output, status = run_entrypoint("../bin/web", "--help")

    assert_predicate status, :success?, output
    assert_equal ["#{@directory}:db:prepare", "#{@directory}/nested:server --help"], File.readlines(File.join(@directory, "calls"), chomp: true)
  end

  def test_standalone_commands_do_not_require_application_gems
    gemfile = File.join(@directory, "Gemfile")
    File.write(gemfile, "gem 'missing_application_gem'\n")
    output, status = run_entrypoint(RbConfig.ruby, "-e", "print 'ready'", env: { "BUNDLE_GEMFILE" => gemfile })

    assert_predicate status, :success?, output
    assert_equal "ready", output
  end

  def test_explicit_dependency_install_can_update_a_stale_lockfile
    gemfile = File.join(@directory, "Gemfile")
    File.write(gemfile, "source 'https://rubygems.org'\ngem 'rake'\n")
    environment = { "BUNDLE_GEMFILE" => gemfile, "BUNDLE_LOCKFILE" => "#{gemfile}.lock", "BUNDLE_FROZEN" => "false", "BUNDLE_LOCKFILE_CHECKSUMS" => "false" }
    output, status = Bundler.with_original_env { Open3.capture2e(environment, "bundle", "lock", "--local") }

    assert_predicate status, :success?, output
    File.open(gemfile, "a") { |file| file.puts "gem 'json'" }
    output, status = run_entrypoint("env", "BUNDLE_FROZEN=false", "bundle", "install", "--local", env: environment.merge("BUNDLE_FROZEN" => "true"))

    assert_predicate status, :success?, output
    output, status = Bundler.with_original_env { Open3.capture2e(environment.merge("BUNDLE_FROZEN" => "true"), "bundle", "check") }

    assert_predicate status, :success?, output
  end

  def test_absolute_production_runtime_requires_secret
    output, status = run_entrypoint(File.join(@directory, "bin/rails"), "server", env: { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => nil })

    assert_equal 1, status.exitstatus, output
    assert_includes output, "Missing SECRET_KEY_BASE"
    refute_path_exists File.join(@directory, "calls")
  end

  def test_missing_program_fails_with_actionable_message
    output, status = run_entrypoint("missing-project-program")

    assert_equal 127, status.exitstatus, output
    assert_includes output, "missing-project-program"
    assert_includes output, "run just setup"
  end

  def test_single_string_is_an_exact_program_name
    output, status = run_entrypoint("printf should-not-run")

    assert_equal 127, status.exitstatus, output
    assert_includes output, "Command [printf should-not-run] is unavailable"
  end

  def test_single_executable_path_with_spaces_runs_without_splitting
    program = File.join(@directory, "tool with spaces")
    File.write(program, "#!/bin/sh\nprintf single-program-output\nexit 37\n")
    FileUtils.chmod(0o755, program)
    output, status = run_entrypoint(program)

    assert_equal 37, status.exitstatus, output
    assert_equal "single-program-output", output
  end

  def test_multiple_arguments_keep_empty_and_literal_values
    output, status = run_entrypoint(RbConfig.ruby, "-rjson", "-e", "print JSON.generate(ARGV); exit 37", "--", "", "a b", "$(literal);*")

    assert_equal 37, status.exitstatus, output
    assert_equal '["","a b","$(literal);*"]', output
  end

  private

  def run_entrypoint(*, env: {})
    environment = { "PATH" => "#{@directory}:#{ENV.fetch('PATH')}", "RAILS_ENV" => "development", "ENTRYPOINT_LOG" => File.join(@directory, "calls"), "BUNDLE_LOCKFILE" => File.join(@directory, "Gemfile.lock") }
    Bundler.with_original_env do
      Open3.capture2e(environment.merge(env), RbConfig.ruby, File.join(@directory, "bin/docker-entrypoint"), *, chdir: File.join(@directory, "nested"))
    end
  end
end

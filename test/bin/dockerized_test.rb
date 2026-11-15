# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "timeout"

# Standalone Minitest does not provide Rails assert_not aliases.
# rubocop:disable Rails/RefuteMethods
class DockerizedTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("r3x dockerized ")
    @runner = File.join(@directory, "dockerized.sh")
    @log = File.join(@directory, "calls.jsonl")
    FileUtils.cp(ENV.fetch("DOCKERIZED_UNDER_TEST", File.expand_path("../../dockerized.sh", __dir__)), @runner)
    File.write(File.join(@directory, "docker"), <<~RUBY)
      #!#{RbConfig.ruby}
      require "json"
      plugin = File.basename($PROGRAM_NAME) == "docker-compose"
      ARGV.unshift("compose") if plugin
      File.open(ENV.fetch("DOCKER_TEST_LOG"), "a") do |log|
        log.puts JSON.generate(binary: plugin ? "plugin" : "docker", args: ARGV, user: ENV["DOCKERIZED_USER"], project: ENV["COMPOSE_PROJECT_NAME"], bundle: ENV["DOCKER_BUNDLE_DIR"], cache: ENV["DOCKER_CACHE_DIR"])
      end
      case ARGV.first
      when "info"
        if ARGV.last.include?("ClientInfo.Plugins")
          puts File.join(File.dirname($PROGRAM_NAME), "docker-compose") unless ENV["DOCKER_TEST_MODE"] == "compose-missing"
          exit 0
        end
        abort "Docker unavailable" if ENV["DOCKER_TEST_MODE"] == "unavailable"
        puts case ENV["DOCKER_TEST_MODE"]
        when "rootful" then '["name=seccomp"]'
        when "userns" then '["name=userns"]'
        else '["name=rootless"]'
        end
      when "image"
        exit(ENV["DOCKER_TEST_MODE"] == "image-missing" ? 42 : 0)
      else
        if ARGV.include?("config")
          puts "fixture:dev"
        elsif ARGV.include?("run")
          if ENV["DOCKER_TEST_SIGNALS"]
            Signal.trap("TERM") do
              File.write(ENV.fetch("DOCKER_TEST_STOPPED"), "TERM") if plugin
              exit(plugin ? 43 : 130)
            end
            File.write(ENV.fetch("DOCKER_TEST_READY"), "ready")
            sleep 10
          end
          STDOUT.write(STDIN.read) if ENV["DOCKER_TEST_STREAMS"]
          STDERR.write("fixture stderr") if ENV["DOCKER_TEST_STREAMS"]
          exit Integer(ENV.fetch("DOCKER_TEST_EXIT", "0"))
        end
      end
    RUBY
    File.write(File.join(@directory, "id"), <<~RUBY)
      #!#{RbConfig.ruby}
      puts ENV.fetch(ARGV == ["-u"] ? "DOCKER_TEST_UID" : "DOCKER_TEST_GID", "1234")
    RUBY
    FileUtils.ln_s("docker", File.join(@directory, "docker-compose"))
    %w[docker id].each { |name| FileUtils.chmod(0o755, File.join(@directory, name)) }
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_commands_keep_arguments_streams_and_exit_status
    output, error, status = Open3.capture3(environment.merge("DOCKER_TEST_EXIT" => "37", "DOCKER_TEST_STREAMS" => "true"), @runner,
      "ruby", "-e", "puts 'hello world'", "", stdin_data: "input\n", chdir: @directory)

    assert_equal 37, status.exitstatus
    assert_equal "input\n", output
    assert_equal "fixture stderr", error
    assert_equal ["ruby", "-e", "puts 'hello world'", ""], calls.last.fetch("args").last(4)
    assert_includes calls.last.fetch("args"), "-T"
    assert_includes calls.last.fetch("args"), "--pull"
    refute calls.any? { |call| (call.fetch("args") & %w[build pull install]).any? }
    refute_path_exists File.join(@directory, ".bundle/gems")
  end

  def test_subdirectory_preserves_cwd_and_command_arguments
    nested = File.join(@directory, "sub directory")
    FileUtils.mkdir_p(nested)
    output, status = run_wrapper("../bin/rails", "console", "a b", "", chdir: nested)

    assert_predicate status, :success?, output
    args = calls.last.fetch("args")

    assert_equal nested, args[args.index("--workdir") + 1]
    assert_equal ["../bin/rails", "console", "a b", ""], args.last(4)
    assert_equal ["compose", "--project-directory", @directory, "--file", File.join(@directory, "compose.yaml")], args.first(5)
  end

  def test_foreign_cwd_is_rejected_before_docker
    outside = Dir.mktmpdir("foreign worktree ")
    output, status = run_wrapper("ruby", "--version", chdir: outside)

    assert_equal 1, status.exitstatus, output
    assert_includes output, "outside this checkout"
    refute_path_exists @log
  ensure
    FileUtils.remove_entry(outside) if outside
  end

  def test_worktrees_own_their_compose_name_and_cache_paths
    other = Dir.mktmpdir("r3x worktree ")
    FileUtils.cp(@runner, File.join(other, "dockerized.sh"))
    output, status = run_wrapper("compose", "ps", overrides: { "COMPOSE_PROJECT_NAME" => "foreign", "HOME" => nil, "XDG_CACHE_HOME" => "/foreign" })

    assert_predicate status, :success?, output
    first = calls.last
    output, status = Open3.capture2e(environment, File.join(other, "dockerized.sh"), "compose", "ps", chdir: other)

    assert_predicate status, :success?, output
    second = calls.last

    refute_equal first.fetch("project"), second.fetch("project")
    assert_equal File.join(@directory, ".bundle/gems"), first.fetch("bundle")
    assert_equal File.join(other, ".dev/cache"), second.fetch("cache")
    refute_path_exists File.join(other, ".dev/cache")
  ensure
    FileUtils.remove_entry(other) if other
  end

  def test_missing_image_never_builds_or_runs
    output, status = run_wrapper("ruby", "--version", overrides: { "DOCKER_TEST_MODE" => "image-missing" })

    assert_equal 1, status.exitstatus, output
    assert_includes output, "just setup"
    refute calls.any? { |call| (call.fetch("args") & %w[build run pull]).any? }
  end

  def test_setup_explicitly_prepares_all_service_images_bundle_and_plugins
    output, status = run_wrapper("setup")

    assert_predicate status, :success?, output
    commands = calls.select { |call| call.fetch("args").first == "compose" }.map { |call| call.fetch("args").drop(7) }

    assert_equal %w[build app], commands[0]
    assert_equal %w[pull --policy missing js-tests dockerfile-lint postgres], commands[1]
    assert_equal %w[bundle install], commands[2].last(2)
    assert_equal ["./bin/dprint", "install"], commands[3].last(2)
    assert_equal Process.uid, File.stat(File.join(@directory, ".bundle/gems")).uid
    assert_path_exists File.join(@directory, ".dev/cache")
  end

  def test_up_explicitly_disables_builds_and_pulls
    output, status = run_wrapper("up")

    assert_predicate status, :success?, output
    assert_equal ["up", "--no-build", "--pull", "never", "--exit-code-from", "app", "app"], calls.last.fetch("args").last(7)
  end

  def test_up_rejects_extra_arguments_with_explicit_compose_hint
    output, status = run_wrapper("up", "--pull", "always")

    assert_equal 2, status.exitstatus, output
    assert_includes output, "Use ./dockerized.sh compose"
    refute calls.any? { |call| call.fetch("args").include?("up") }
  end

  def test_rootful_uses_host_uid_and_gid
    output, status = run_wrapper("compose", "ps", overrides: { "DOCKER_TEST_MODE" => "rootful", "DOCKER_TEST_UID" => "1234", "DOCKER_TEST_GID" => "5678" })

    assert_predicate status, :success?, output
    assert_equal "1234:5678", calls.last.fetch("user")
  end

  def test_unsupported_or_unavailable_daemons_fail_before_containers
    [["userns", "userns-remap"], ["unavailable", "Could not verify Docker daemon"], ["rootful", "host root"]].each do |mode, message|
      FileUtils.rm_f(@log)
      output, status = run_wrapper("compose", "ps", overrides: { "DOCKER_TEST_MODE" => mode, "DOCKER_TEST_UID" => "0" })

      assert_equal 1, status.exitstatus, output
      assert_includes output, message
      assert_equal 1, calls.length
    end
  end

  def test_just_tests_owns_root_and_preserves_variadic_arguments
    FileUtils.cp(File.expand_path("../../justfile", __dir__), File.join(@directory, "justfile"))
    nested = File.join(@directory, "nested")
    FileUtils.mkdir_p(nested)
    arguments = ["test/path with spaces.rb", "", "$(touch injected)", "; touch injected"]
    output, status = Open3.capture2e(environment, "just", "--justfile", File.join(@directory, "justfile"), "tests", *arguments, chdir: nested)

    assert_predicate status, :success?, output
    args = calls.last.fetch("args")

    assert_equal @directory, args[args.index("--workdir") + 1]
    assert_equal ["bin/rails", "test", *arguments], args.last(6)
    refute_path_exists File.join(@directory, "injected")
  rescue Errno::ENOENT
    skip "Optional recipe integration check: just is not installed"
  end

  def test_term_reaches_plugin_and_preserves_child_exit_status
    ready = File.join(@directory, "ready")
    stopped = File.join(@directory, "stopped")
    env = environment.merge("DOCKER_TEST_SIGNALS" => "true", "DOCKER_TEST_READY" => ready, "DOCKER_TEST_STOPPED" => stopped)
    pid = Process.spawn(env, @runner, "ruby", "-e", "sleep", chdir: @directory, out: File::NULL, err: File::NULL)
    Timeout.timeout(5) { sleep 0.01 until File.exist?(ready) }
    Process.kill("TERM", pid)
    _, status = Process.wait2(pid)
    pid = nil

    assert_equal 43, status.exitstatus
    assert_equal "TERM", File.read(stopped)
    assert_equal "plugin", calls.last.fetch("binary")
  ensure
    if pid
      Process.kill("KILL", pid)
      Process.wait(pid)
    end
  end

  def test_missing_compose_plugin_fails_with_install_instruction
    output, status = run_wrapper("compose", "ps", overrides: { "DOCKER_TEST_MODE" => "compose-missing" })

    assert_equal 1, status.exitstatus, output
    assert_includes output, "install it before running just setup"
    refute calls.any? { |call| call.fetch("args").first == "compose" }
  end

  private

  def environment
    { "PATH" => "#{@directory}:#{ENV.fetch('PATH')}", "DOCKER_TEST_LOG" => @log, "COMPOSE_PROJECT_NAME" => nil }
  end

  def run_wrapper(*, overrides: {}, chdir: @directory)
    Open3.capture2e(environment.merge(overrides), @runner, *, chdir:)
  end

  def calls
    File.readlines(@log).map { |line| JSON.parse(line) }
  end
end

# rubocop:enable Rails/RefuteMethods

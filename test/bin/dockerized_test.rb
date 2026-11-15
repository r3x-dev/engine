# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

class DockerizedTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("r3x dockerized ")
    @log = File.join(@directory, "calls.jsonl")
    @runner = File.join(@directory, "dockerized.sh")
    FileUtils.cp(File.expand_path("../../dockerized.sh", __dir__), @runner)
    FileUtils.mkdir_p(File.join(@directory, ".dev/bin"))
    FileUtils.cp(File.expand_path("../../.dev/run", __dir__), File.join(@directory, ".dev/run"))
    %w[ruby-lsp ruby bundle dprint].each do |name|
      FileUtils.ln_s("../run", File.join(@directory, ".dev/bin", name))
    end
    FileUtils.mkdir_p(File.join(@directory, "bin"))
    File.write(File.join(@directory, "bin/rails"), "")
    @cache_home = File.join(@directory, "cache")
    File.write(File.join(@directory, "Gemfile.lock"), "")
    File.write(File.join(@directory, "docker"), <<~RUBY)
      #!#{RbConfig.ruby}
      require "json"
      File.open(ENV.fetch("DOCKER_TEST_LOG"), "a") do |log|
        log.puts(JSON.generate({
          "args" => ARGV,
          "user" => ENV["DOCKERIZED_USER"],
          "project" => ENV["COMPOSE_PROJECT_NAME"],
          "bundle" => ENV["DOCKER_BUNDLE_DIR"],
          "cache" => ENV["DOCKER_CACHE_DIR"],
          "bundle_exists" => File.directory?(ENV["DOCKER_BUNDLE_DIR"]),
          "cache_exists" => ENV["DOCKER_CACHE_DIR"] && File.directory?(ENV["DOCKER_CACHE_DIR"]),
        }))
      end
      if ARGV.first == "info"
        abort "Docker unavailable" if ENV["DOCKER_TEST_MODE"] == "unavailable"
        puts case ENV.fetch("DOCKER_TEST_MODE", "rootless")
        when "rootful", "rootful-root"
          '["name=seccomp"]'
        when "userns"
          '["name=seccomp","name=userns"]'
        else
          '["name=rootless"]'
        end
      elsif ARGV.first == "image"
        exit(ENV["DOCKER_TEST_MODE"] == "image-missing" ? 42 : 0)
      else
        puts "fixture:dev" if ARGV.include?("config")
        exit Integer(ENV.fetch("DOCKER_TEST_EXIT", "0"))
      end
    RUBY
    File.write(File.join(@directory, "id"), <<~RUBY)
      #!#{RbConfig.ruby}
      case ARGV
      when ["-u"] then puts ENV.fetch("DOCKER_TEST_UID", Process.uid)
      when ["-g"] then puts ENV.fetch("DOCKER_TEST_GID", Process.gid)
      else abort "Unexpected id arguments: " + ARGV.inspect
      end
    RUBY
    %w[docker id].each { |name| FileUtils.chmod(0o755, File.join(@directory, name)) }
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_commands_keep_argument_boundaries_and_exit_status
    prepare_bundle
    output, status = run_wrapper("ruby", "-e", "puts 'hello world'", "", exit_code: "37")

    assert_equal 37, status.exitstatus, output
    assert_equal ["compose", "--progress", "quiet", "run", "--pull", "never", "--rm", "--no-deps", "-T", "app", "ruby", "-e", "puts 'hello world'", ""], calls.last.fetch("args")
  end

  def test_compose_commands_use_the_same_guard
    output, status = run_wrapper("compose", "up", "--build")

    assert_predicate status, :success?, output
    assert_equal ["compose", "--progress", "quiet", "up", "--build"], calls.last.fetch("args")
    assert_equal "0:0", calls.last.fetch("user")
  end

  def test_compose_project_name_override_is_preserved
    output, status = run_wrapper("compose", "ps", project_name: "fixture-editor")

    assert_predicate status, :success?, output
    assert_equal "fixture-editor", calls.last.fetch("project")
  end

  def test_cache_paths_do_not_depend_on_home_or_xdg_cache_home
    output, status = run_wrapper("compose", "ps", overrides: { "HOME" => nil, "XDG_CACHE_HOME" => nil })

    assert_predicate status, :success?, output
    assert_equal bundle_dir, calls.last.fetch("bundle")
    assert_equal cache_dir, calls.last.fetch("cache")
  end

  def test_cache_paths_ignore_a_foreign_xdg_cache_home
    output, status = run_wrapper("compose", "ps")

    assert_predicate status, :success?, output
    assert_equal bundle_dir, calls.last.fetch("bundle")
    assert_equal cache_dir, calls.last.fetch("cache")
    refute_path_exists @cache_home
  end

  def test_cache_paths_follow_the_captured_checkout_root_and_isolate_worktrees
    outside = Dir.mktmpdir("r3x outside ")
    other = Dir.mktmpdir("r3x worktree ")
    other_runner = File.join(other, "dockerized.sh")
    FileUtils.cp(@runner, other_runner)

    output, status = run_wrapper("compose", "ps", chdir: outside)

    assert_predicate status, :success?, output
    first = calls.last

    File.write(@log, "")
    environment = shell_environment.merge("COMPOSE_PROJECT_NAME" => nil)
    output, status = Open3.capture2e(environment, "bash", other_runner, "compose", "ps", chdir: outside)

    assert_predicate status, :success?, output
    second = calls.last

    assert_equal bundle_dir, first.fetch("bundle")
    assert_equal cache_dir, first.fetch("cache")
    assert_equal File.join(other, ".bundle/gems"), second.fetch("bundle")
    assert_equal File.join(other, ".dev/cache"), second.fetch("cache")
    # This suite uses standalone Minitest assertions.
    refute_equal first.fetch("project"), second.fetch("project") # rubocop:disable Rails/RefuteMethods
    refute_path_exists bundle_dir
    refute_path_exists cache_dir
    refute_path_exists File.join(other, ".bundle")
    refute_path_exists File.join(other, ".dev/cache")
  ensure
    FileUtils.remove_entry(outside) if outside && File.exist?(outside)
    FileUtils.remove_entry(other) if other && File.exist?(other)
  end

  def test_rootful_docker_uses_the_host_uid_and_gid
    prepare_bundle
    output, status = run_wrapper("ruby", "--version", mode: "rootful", uid: "1234", gid: "5678")

    assert_predicate status, :success?, output
    assert_equal "1234:5678", calls.last.fetch("user")
    assert_equal project_name, calls.last.fetch("project")
  end

  def test_rootful_userns_remap_is_refused_before_starting_containers
    output, status = run_wrapper("ruby", "--version", mode: "userns")

    assert_equal 1, status.exitstatus, output
    assert_includes output, "userns-remap"
    assert_equal 1, calls.length
  end

  def test_rootful_docker_is_refused_when_host_user_is_root
    output, status = run_wrapper("ruby", "--version", mode: "rootful-root", uid: "0", gid: "0")

    assert_equal 1, status.exitstatus, output
    assert_includes output, "host root"
    assert_equal 1, calls.length
  end

  def test_unavailable_docker_is_refused_before_starting_containers
    output, status = run_wrapper("compose", "up", mode: "unavailable")

    assert_equal 1, status.exitstatus, output
    assert_includes output, "Could not verify Docker daemon"
    assert_equal 1, calls.length
  end

  def test_setup_creates_local_bundle_and_tool_caches_as_host_user
    refute_path_exists bundle_dir
    refute_path_exists cache_dir
    output, status = run_wrapper("setup")

    assert_predicate status, :success?, output
    assert_equal Process.uid, File.stat(bundle_dir).uid
    assert_equal Process.gid, File.stat(bundle_dir).gid
    assert_equal Process.uid, File.stat(cache_dir).uid
    assert_equal Process.gid, File.stat(cache_dir).gid
    assert_equal ["compose", "--progress", "quiet", "build", "app"], calls[1].fetch("args")
    assert_includes calls[2].fetch("args"), "bundle"
    assert_includes calls[2].fetch("args"), "install"
    assert_equal ["./bin/dprint", "resolved-config", "--config", "dprint.json", "--file", "compose.yaml"], calls[3].fetch("args").last(6)
    assert_equal ["0:0"], calls.drop(1).map { |call| call.fetch("user") }.uniq
    assert_equal [true], calls.drop(1).map { |call| call.fetch("bundle_exists") }.uniq
    assert_equal [true], calls.drop(1).map { |call| call.fetch("cache_exists") }.uniq
  end

  def test_setup_uses_the_current_uid_and_gid_on_rootful_docker
    output, status = run_wrapper("setup", mode: "rootful", uid: "1234", gid: "5678")

    assert_predicate status, :success?, output
    assert_equal ["1234:5678"], calls.drop(1).map { |call| call.fetch("user") }.uniq
    assert_equal Process.uid, File.stat(bundle_dir).uid
    assert_equal Process.uid, File.stat(cache_dir).uid
  end

  def test_editor_runs_only_with_prepared_image_and_no_app_boot
    prepare_bundle
    output, status = run_wrapper("lsp")

    assert_predicate status, :success?, output
    assert_includes calls.last.fetch("args"), "--no-deps"
    assert_includes calls.last.fetch("args"), "-T"
    assert_includes calls.last.fetch("args"), "--pull"
    assert_includes calls.last.fetch("args"), "never"
    assert_equal "editor", calls.last.fetch("args").last
    assert calls.none? { |call| call.fetch("args").include?("build") || call.fetch("args").include?("up") }
  end

  def test_editor_missing_image_or_lockfile_never_builds_or_installs
    prepare_bundle
    output, status = run_wrapper("lsp", mode: "image-missing")

    assert_equal 1, status.exitstatus, output
    assert_includes output, "setup"
    assert calls.none? { |call| call.fetch("args").include?("run") || call.fetch("args").include?("build") }

    FileUtils.rm(File.join(@directory, "Gemfile.lock"))
    File.write(@log, "")
    output, status = run_wrapper("lsp")

    assert_equal 1, status.exitstatus, output
    assert_includes output, "setup"
    assert_equal 1, calls.length
  end

  def test_editor_and_dprint_with_missing_image_never_build_or_run
    prepare_bundle
    ["lsp", "bin/dprint"].each do |*command|
      File.write(@log, "")
      output, status = run_wrapper(*command, mode: "image-missing")

      assert_equal 1, status.exitstatus, output
      assert_includes output, "run ./dockerized.sh setup"
      assert calls.none? { |call| call.fetch("args").include?("run") || call.fetch("args").include?("build") }
    end
  end

  def test_dprint_invocation_never_builds_pulls_or_installs
    prepare_bundle
    output, status = run_wrapper("bin/dprint", "fmt")

    assert_predicate status, :success?, output
    assert_empty output
    assert_equal ["compose", "--progress", "quiet", "run", "--pull", "never", "--rm", "--no-deps", "-T", "app", "bin/dprint", "fmt"], calls.last.fetch("args")
  end

  %w[bash zsh].each do |shell|
    define_method("test_sourcing_in_#{shell}_preserves_the_shell_and_routes_commands") do
      prepare_bundle
      File.write(@log, "")
      output, status = run_shell(shell, <<~SHELL)
        before_options=$-
        before_pwd=$PWD
        ruby() { :; }
        eval 'function bin/old { :; }'
        _dockerized_path_functions=(bin/old)
        bundle() { :; }
        source "$1"
        if typeset -f bin/old >/dev/null 2>&1; then exit 81; fi
        source "$1"
        if typeset -f bin/old >/dev/null 2>&1; then exit 81; fi
        test "$before_options" = "$-" || exit 91
        test "$before_pwd" = "$PWD" || exit 92
        [[ "$PATH" == "$PWD/.dev/bin:"* ]] || exit 93
        printf 'shell-alive\\n'
        bundle exec ruby -e 'puts "hello world"'
        bin/rails test 'path with spaces'
        ./bin/rails --version
      SHELL

      assert_predicate status, :success?, "#{shell}: #{output}"
      assert_equal "shell-alive\n", output
      commands = calls.select { |call| call.fetch("args").include?("run") }

      assert_equal ["bundle", "exec", "ruby", "-e", 'puts "hello world"'], commands[0].fetch("args").last(5)
      assert_equal ["bin/rails", "test", "path with spaces"], commands[1].fetch("args").last(3)
      assert_equal ["./bin/rails", "--version"], commands[2].fetch("args").last(2)
    end

    define_method("test_sourcing_in_#{shell}_does_not_contact_docker_and_commands_propagate_failures") do
      FileUtils.rm_f(@log)
      output, status = run_shell(shell, 'source "$1"')

      assert_predicate status, :success?, "#{shell}: #{output}"
      assert_empty output
      refute_path_exists @log
      refute_path_exists bundle_dir
      refute_path_exists cache_dir

      prepare_bundle
      output, status = run_shell(shell, "source \"$1\"\nruby --version", exit_code: "37")

      assert_equal 37, status.exitstatus, "#{shell}: #{output}"
    end
  end


  def test_ruby_lsp_path_command_uses_the_existing_lsp_runner
    prepare_bundle
    environment = shell_environment
    environment["PATH"] = "#{@directory}/.dev/bin:#{environment.fetch("PATH")}"
    output, status = Open3.capture2e(environment, "ruby-lsp", chdir: @directory)

    assert_predicate status, :success?, output
    assert_equal "editor", calls.last.fetch("args").last
    assert calls.none? { |call| call.fetch("args").include?("build") || call.fetch("args").include?("install") }
  end

  def test_sourced_dprint_command_uses_the_project_dispatcher
    prepare_bundle
    output, status = run_shell("bash", 'source "$1"; dprint fmt')

    assert_predicate status, :success?, output
    assert_empty output
    assert_equal ["compose", "--progress", "quiet", "run", "--pull", "never", "--rm", "--no-deps", "-T", "app", "bin/dprint", "fmt"], calls.last.fetch("args")
    assert calls.none? { |call| call.fetch("args").include?("build") || call.fetch("args").include?("install") }
  end

  def test_dprint_wrapper_uses_its_project_from_a_different_directory
    outside = Dir.mktmpdir("r3x outside ")
    prepare_bundle
    File.write(@log, "")
    environment = shell_environment
    environment["PATH"] = "#{@directory}/.dev/bin:#{environment.fetch("PATH")}"
    output, status = Open3.capture2e(environment, "dprint", "fmt", chdir: outside)

    assert_predicate status, :success?, output
    assert_equal ["compose", "--progress", "quiet", "run", "--pull", "never", "--rm", "--no-deps", "-T", "app", "bin/dprint", "fmt"], calls.last.fetch("args")
  ensure
    FileUtils.remove_entry(outside) if outside && File.exist?(outside)
  end

  def test_sourcing_another_project_replaces_project_bin
    other = Dir.mktmpdir("r3x other ")
    File.write(@log, "")
    other_runner = File.join(other, "dockerized.sh")
    FileUtils.cp(@runner, other_runner)
    FileUtils.mkdir_p(File.join(other, ".dev/bin"))
    FileUtils.mkdir_p(File.join(other, "bin"))
    File.write(File.join(other, "bin/rails"), "")
    FileUtils.cp(File.join(@directory, ".dev/run"), File.join(other, ".dev/run"))
    FileUtils.ln_s("../run", File.join(other, ".dev/bin/dprint"))

    environment = shell_environment
    environment["OTHER_DOCKERIZED_RUNNER"] = other_runner
    output, status = Open3.capture2e(environment, "bash", "-c", <<~SH, "shell-test", @runner, chdir: @directory)
      source "$1"
      source "$OTHER_DOCKERIZED_RUNNER"
      source "$1"
      [[ "$PATH" == "${1%/*}/.dev/bin:"* ]]
      case ":$PATH:" in *":${OTHER_DOCKERIZED_RUNNER%/dockerized.sh}/.dev/bin:"*) exit 92 ;; esac
    SH

    assert_predicate status, :success?, output
    assert_empty output
    assert_empty calls
  ensure
    FileUtils.remove_entry(other) if other && File.exist?(other)
  end

  private

  def run_wrapper(*, mode: "rootless", exit_code: "0", uid: Process.uid.to_s, gid: Process.gid.to_s, project_name: nil, overrides: {}, chdir: @directory)
    environment = shell_environment(mode:, exit_code:, uid:, gid:)
    environment["COMPOSE_PROJECT_NAME"] = project_name
    Open3.capture2e(environment.merge(overrides), "bash", @runner, *, chdir:)
  end

  def run_shell(shell, script, exit_code: "0", chdir: @directory)
    Open3.capture2e(shell_environment(exit_code:), shell, "-c", script, "shell-test", @runner, chdir:)
  rescue Errno::ENOENT
    raise unless shell == "zsh"
    skip "Optional host-shell compatibility check: Zsh is not installed"
  end

  def shell_environment(mode: "rootless", exit_code: "0", uid: Process.uid.to_s, gid: Process.gid.to_s)
    {
      "PATH"             => "#{@directory}:#{ENV.fetch('PATH')}",
      "DOCKER_TEST_LOG"  => @log,
      "DOCKER_TEST_MODE" => mode,
      "DOCKER_TEST_EXIT" => exit_code,
      "DOCKER_TEST_UID"  => uid,
      "DOCKER_TEST_GID"  => gid,
      "XDG_CACHE_HOME"   => @cache_home,
    }
  end

  def calls
    File.readlines(@log).map { |line| JSON.parse(line) }
  end

  def bundle_dir
    File.join(@directory, ".bundle/gems")
  end

  def cache_dir
    File.join(@directory, ".dev/cache")
  end

  def project_name
    slug = File.basename(@directory).downcase.gsub(/[^a-z0-9_-]/, "-")[0, 32]
    "dev-#{slug}-#{Digest::SHA256.hexdigest(@directory)[0, 12]}"
  end

  def prepare_bundle
    FileUtils.mkdir_p(File.join(bundle_dir, ".cache"))
  end
end

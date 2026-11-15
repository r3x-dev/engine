# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"

class PreCommitTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("r3x-pre-commit")
    git("init", "-q")
    File.write(path("example.yml"), "first: staged\nsecond: staged\n")
    git("add", "example.yml")
    File.write(path("example.yml"), "first: staged\nsecond: unstaged\n")
    script("dockerized.sh", "exit 0")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_hook_preserves_partially_staged_yaml
    script("just", "exit 0")
    before_index = git("show", ":example.yml")
    before_worktree = File.read(path("example.yml"))

    output, status = run_hook

    assert_predicate status, :success?, output
    assert_equal before_index, git("show", ":example.yml")
    assert_equal before_worktree, File.read(path("example.yml"))
  end

  def test_hook_propagates_ci_failure_without_staging_changes
    script("just", "exit 37")
    before_index = git("show", ":example.yml")

    output, status = run_hook

    assert_equal 37, status.exitstatus, output
    assert_equal before_index, git("show", ":example.yml")
    assert_equal "first: staged\nsecond: unstaged\n", File.read(path("example.yml"))
  end

  private

  def path(name) = File.join(@directory, name)

  def script(name, body)
    File.write(path(name), "#!/bin/sh\n#{body}\n")
    FileUtils.chmod(0o755, path(name))
  end

  def git(*)
    output, status = Open3.capture2e("git", "--no-pager", *, chdir: @directory)
    raise output unless status.success?
    output
  end

  def run_hook
    hook = File.expand_path("../../.githooks/pre-commit", __dir__)
    Open3.capture2e({ "PATH" => "#{@directory}:#{ENV.fetch('PATH')}" }, "bash", hook, chdir: @directory)
  end
end

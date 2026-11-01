# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

class BundlerAuditTest < ActiveSupport::TestCase
  GIT_ENV = { "GIT_DIR" => nil, "GIT_WORK_TREE" => nil, "GIT_INDEX_FILE" => nil, "GIT_COMMON_DIR" => nil }.freeze

  test "default audit refreshes an existing database and detects a newly published advisory" do
    with_database do |remote, database|
      advisories = File.join(remote, "gems", "rack")
      FileUtils.mkdir_p(advisories)
      File.write(File.join(advisories, "GHSA-aaaa-bbbb-cccc.yml"), <<~YAML)
        ---
        gem: rack
        ghsa: aaaa-bbbb-cccc
        url: https://example.test/security/advisory
        title: Security audit regression fixture
        date: 2026-01-01
        description: Synthetic advisory for the local audit regression.
        patched_versions:
          - ">= 999.0.0"
      YAML
      commit_database(remote)

      output, status = audit(database)

      assert_equal 1, status.exitstatus, output
      assert_includes output, "Security audit regression fixture"
    end
  end

  test "default audit fails when its database cannot be refreshed" do
    with_database do |remote, database|
      git(database, "remote", "set-url", "origin", "#{remote}-missing")

      output, status = audit(database)

      assert_equal 1, status.exitstatus, output
      assert_includes output, "failed to update"
      assert_not_includes output, "No vulnerabilities found"
    end
  end

  test "explicit offline check can use an existing database without refreshing it" do
    with_database do |remote, database|
      git(database, "remote", "set-url", "origin", "#{remote}-missing")

      output, status = audit(database, "check", "--no-update")

      assert_predicate status, :success?, output
      assert_includes output, "No vulnerabilities found"
    end
  end

  private

  def with_database
    Dir.mktmpdir("r3x-audit-test-") do |directory|
      remote = File.join(directory, "upstream")
      database = File.join(directory, "database")
      FileUtils.mkdir_p(remote)
      git(remote, "init", "--initial-branch=master")
      File.write(File.join(remote, "README.md"), "Synthetic advisory database\n")
      commit_database(remote)
      git(directory, "clone", remote, database)
      yield remote, database
    end
  end

  def commit_database(path)
    git(path, "add", ".")
    git(path, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", "commit", "-m", "Update fixture database")
  end

  def git(path, *)
    output, error, status = Open3.capture3(GIT_ENV, "git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "-C", path, *)
    raise "Fixture git command failed: #{output}#{error}" unless status.success?
  end

  def audit(database, *)
    output, error, status = Open3.capture3(
      GIT_ENV.merge("BUNDLER_AUDIT_DB" => database),
      RbConfig.ruby,
      Rails.root.join("bin/bundler-audit").to_s,
      *,
      chdir: Rails.root,
    )
    [output + error, status]
  end
end

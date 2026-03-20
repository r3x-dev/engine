require "test_helper"

# Regression tests for namespace refactoring.
# These catch stale references that bin/rails test + rubocop miss
# because rake tasks, ERB configs, and markdown are not loaded by the test runner.
class NamespaceRefactoringTest < ActiveSupport::TestCase
  REPO_ROOT = Rails.root

  # Maps old deleted file paths to the error message if references to them still exist.
  # These files no longer exist and should not be referenced anywhere.
  REMOVED_FILES = {
    "lib/r3x/trigger_collection.rb"    => "R3x::TriggerCollection",
    "lib/r3x/trigger_execution.rb"     => "R3x::TriggerExecution",
    "lib/r3x/workflow_context.rb"      => "R3x::WorkflowContext",
    "lib/r3x/workflow_execution.rb"    => "R3x::WorkflowExecution",
    "lib/r3x/workflow_pack_loader.rb"  => "R3x::WorkflowPackLoader",
    "lib/r3x/workflow_registry.rb"     => "R3x::WorkflowRegistry"
  }.freeze

  SCAN_EXTENSIONS = %w[.rb .rake .yml .yaml .erb .md].freeze

  test "removed files no longer exist on disk" do
    REMOVED_FILES.each_key do |path|
      full = REPO_ROOT.join(path)
      refute File.exist?(full), "#{path} should have been deleted in the refactoring"
    end
  end

  test "no references to removed constants in non-test files" do
    stale = []

    REMOVED_FILES.each_value do |old_constant|
      scan_files do |file, content|
        next if file.include?("/test/")
        next if file.include?("/.bundle/")

        if content.include?(old_constant)
          line_num = content.lines.index { |l| l.include?(old_constant) }&.succ
          stale << "  #{file}:#{line_num} still references #{old_constant}"
        end
      end
    end

    assert_empty stale, "Found stale references to removed constants:\n#{stale.join("\n")}"
  end

  test "AGENTS.md references existing file paths" do
    agents = REPO_ROOT.join("AGENTS.md")
    skip "AGENTS.md not found" unless File.exist?(agents)

    content = File.read(agents)
    missing = []

    # Extract backtick-quoted paths like `lib/r3x/something.rb`
    content.scan(/`((?:lib|app|config|test|workflows)\/[^`]+\.rb)`/) do |match|
      path = match.first
      # Strip directory globs (e.g., `lib/r3x/triggers/*.rb` -> check dir)
      check_path = path.include?("*") ? File.dirname(path.sub(/\*.*$/, "")) : path
      full = REPO_ROOT.join(check_path)
      unless File.exist?(full)
        missing << "  AGENTS.md references `#{path}` but #{check_path} does not exist"
      end
    end

    assert_empty missing, "AGENTS.md has stale file path references:\n#{missing.join("\n")}"
  end

  test "AGENTS.md references existing class names" do
    agents = REPO_ROOT.join("AGENTS.md")
    skip "AGENTS.md not found" unless File.exist?(agents)

    content = File.read(agents)
    missing = []

    # Extract class references like `R3x::WorkflowPackLoader`
    content.scan(/`((?:R3x::[A-Z][a-zA-Z]+(?:::[A-Z][a-zA-Z]+)*))`/) do |match|
      class_name = match.first
      next if class_name.include?("::Workflow::")
      next if class_name.include?("::Triggers::")
      next if class_name.include?("::Client::")
      next if class_name.include?("::Outputs::")
      next if class_name.include?("::Concerns::")
      next if class_name.include?("::Dsl::")
      next if class_name.include?("::Validators::")

      line_with_ref = content.lines.find { |l| l.include?(class_name) }
      next if line_with_ref&.match?(/\*\*Bad\*\*/i) # Bad examples in docs

      begin
        class_name.constantize
      rescue NameError
        missing << "  AGENTS.md references `#{class_name}` but the class does not exist"
      end
    end

    assert_empty missing, "AGENTS.md has stale class references:\n#{missing.join("\n")}"
  end

  private

  def scan_files
    Dir.glob(REPO_ROOT.join("**/*").to_s).each do |path|
      next unless File.file?(path)
      next unless SCAN_EXTENSIONS.include?(File.extname(path))
      next if path.include?("/.bundle/")
      next if path.include?("/node_modules/")
      next if path.include?("/tmp/")

      yield path, File.read(path)
    end
  end
end

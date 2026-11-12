# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

module R3x
  class WorkflowPackLoaderTest < ActiveSupport::TestCase
    setup do
      @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
      R3x::Workflow::PackLoader.load!(rebuild_registry: true)
    end

    teardown do
      ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
    end

    test "loads workflow from external path by convention" do
      workflow_class = R3x::Workflow::Registry.fetch("test_workflow")

      assert_equal Workflows::TestWorkflow, workflow_class
      assert_equal "test_workflow", workflow_class.workflow_key

      schedule = workflow_class.schedulable_triggers.first

      assert schedule
      assert_equal :schedule, schedule.type
      assert_equal "0 * * * *", schedule.cron
      assert_nil schedule.timezone
      assert_equal "0 * * * *", schedule.schedule
    end

    test "raises KeyError for unknown workflow" do
      assert_raises(KeyError) do
        R3x::Workflow::Registry.fetch("unknown_workflow")
      end
    end

    test "skips workflow files with disable pragma" do
      assert_raises(KeyError) do
        R3x::Workflow::Registry.fetch("disabled_workflow")
      end
    end

    test "can run loaded workflow" do
      workflow_class = R3x::Workflow::Registry.fetch("test_workflow")
      result = workflow_class.new.run

      assert result["test"]
      assert_equal "Test workflow executed successfully", result["message"]
    end

    test "logs loaded workflows with workflow tags" do
      output = capture_logged_output do
        R3x::Workflow::PackLoader.load!(rebuild_registry: true)
      end

      assert_includes output, "R3x::Workflow::PackLoader"
      assert_includes output, "r3x.workflow_key=test_workflow"
      assert_includes output, "Loaded workflow class=Workflows::TestWorkflow"
      assert_includes output, "Skipping disabled workflow entrypoint"
    end

    test "requires workflow paths" do
      ENV.delete("R3X_WORKFLOW_PATHS")

      error = assert_raises(ArgumentError) do
        R3x::Workflow::PackLoader.load!(rebuild_registry: true)
      end

      assert_equal "Missing R3X_WORKFLOW_PATHS", error.message
    end

    test "requires at least one workflow entrypoint" do
      Dir.mktmpdir do |dir|
        ENV["R3X_WORKFLOW_PATHS"] = dir

        error = assert_raises(ArgumentError) do
          R3x::Workflow::PackLoader.load!(rebuild_registry: true)
        end

        assert_equal "R3X_WORKFLOW_PATHS contains no workflow.rb entrypoints", error.message
      end
    end

    test "rebuild_registry does not reload already required workflow source" do
      Dir.mktmpdir do |dir|
        workflow_dir = File.join(dir, "reload_semantics")
        workflow_file = File.join(workflow_dir, "workflow.rb")
        FileUtils.mkdir_p(workflow_dir)
        File.write(workflow_file, workflow_source(message: "original"))

        ENV["R3X_WORKFLOW_PATHS"] = dir
        R3x::Workflow::PackLoader.load!(rebuild_registry: true)

        assert_equal "original", R3x::Workflow::Registry.fetch("reload_semantics").new.run.fetch("message")

        File.write(workflow_file, workflow_source(message: "changed"))
        R3x::Workflow::PackLoader.load!(rebuild_registry: true)

        workflow_class = R3x::Workflow::Registry.fetch("reload_semantics")

        assert_equal "original", workflow_class.new.run.fetch("message")
      ensure
        Workflows.send(:remove_const, :ReloadSemantics) if defined?(Workflows::ReloadSemantics)
      end
    end

    test "failed rebuild preserves the complete catalog and can be retried" do
      previous_workflows = Workflow::Registry.all

      with_replacement_catalog do |broken_file|
        error = assert_raises(RuntimeError) do
          Workflow::PackLoader.load!(rebuild_registry: true)
        end

        assert_equal "Broken workflow", error.message
        assert_equal previous_workflows, Workflow::Registry.all

        Workflow::PackLoader.load!

        assert_equal previous_workflows, Workflow::Registry.all

        File.delete(broken_file)
        Workflow::PackLoader.load!(rebuild_registry: true)

        assert_equal [Workflows::ReplacementWorkflow], Workflow::Registry.all
      end
    end

    test "keeps the previous catalog visible while loading its replacement" do
      previous_workflows = Workflow::Registry.all

      with_replacement_catalog do |broken_file|
        File.delete(broken_file)
        Workflow::PackLoader.load!(rebuild_registry: true)

        assert_equal previous_workflows, Workflows::ReplacementWorkflow::OBSERVED_WORKFLOWS
        assert_equal [Workflows::ReplacementWorkflow], Workflow::Registry.all
      end
    end

    test "failed initial load leaves the registry empty and allows another load" do
      with_replacement_catalog do |broken_file|
        Workflow::Registry.reset!
        Workflow::PackLoader::LOADED.make_false

        assert_raises(RuntimeError) do
          Workflow::PackLoader.load!
        end

        assert_empty Workflow::Registry.all

        File.delete(broken_file)
        Workflow::PackLoader.load!

        assert_equal [Workflows::ReplacementWorkflow], Workflow::Registry.all
      end
    end

    test "rejects enabled entrypoints that resolve to the same class before requiring them" do
      previous_workflows = Workflow::Registry.all
      original_report = Workflows.const_get(:Report, false) if Workflows.const_defined?(:Report, false)
      Workflows.send(:remove_const, :Report) if original_report
      report_class = Workflows.const_set(:Report, Class.new(Workflow::Base) do
        define_method(:run) { { "message" => "original" } }
      end)

      with_duplicate_report_catalog do |executions_file|
        error = assert_raises(ArgumentError) do
          Workflow::PackLoader.load!(rebuild_registry: true)
        end

        assert_includes error.message, "Workflows::Report"
        assert_equal previous_workflows, Workflow::Registry.all
        assert_equal "original", report_class.new.run.fetch("message")
        assert_empty report_class.triggers_by_key
        refute_path_exists executions_file
      end
    ensure
      Workflows.send(:remove_const, :Report) if Workflows.const_defined?(:Report, false)
      Workflows.const_set(:Report, original_report) if original_report
    end

    test "allows a disabled entrypoint to share a class identity with an enabled entrypoint" do
      with_duplicate_report_catalog(disabled_indexes: [0]) do |executions_file|
        Workflow::PackLoader.load!(rebuild_registry: true)

        assert_equal [Workflows::Report], Workflow::Registry.all
        assert_equal "second", Workflows::Report.new.run.fetch("message")
        assert_equal ["manual:second"], Workflows::Report.triggers_by_key.keys
        assert_equal "second", File.read(executions_file)
      end
    ensure
      Workflows.send(:remove_const, :Report) if Workflows.const_defined?(:Report, false)
    end

    test "loads a repeated catalog root only once" do
      with_duplicate_report_catalog(root_indexes: [1, 1]) do |executions_file|
        Workflow::PackLoader.load!(rebuild_registry: true)

        assert_equal [Workflows::Report], Workflow::Registry.all
        assert_equal "second", File.read(executions_file)
      end
    ensure
      Workflows.send(:remove_const, :Report) if Workflows.const_defined?(:Report, false)
    end

    private

    def with_replacement_catalog
      Dir.mktmpdir do |dir|
        replacement_dir = File.join(dir, "replacement_workflow")
        broken_dir = File.join(dir, "broken_workflow")
        FileUtils.mkdir_p([replacement_dir, broken_dir])
        File.write(File.join(replacement_dir, "workflow.rb"), <<~RUBY)
          module Workflows
            class ReplacementWorkflow < R3x::Workflow::Base
              OBSERVED_WORKFLOWS = R3x::Workflow::Registry.all

              def run
              end
            end
          end
        RUBY
        broken_file = File.join(broken_dir, "workflow.rb")
        File.write(broken_file, 'raise "Broken workflow"')
        ENV["R3X_WORKFLOW_PATHS"] = [replacement_dir, broken_dir].join(File::PATH_SEPARATOR)

        yield broken_file
      end
    ensure
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
      Workflow::PackLoader.load!(rebuild_registry: true)
      Workflows.send(:remove_const, :ReplacementWorkflow) if defined?(Workflows::ReplacementWorkflow)
    end

    def workflow_source(message:)
      <<~RUBY
        module Workflows
          class ReloadSemantics < R3x::Workflow::Base
            def run
              { "message" => #{message.inspect} }
            end
          end
        end
      RUBY
    end

    def with_duplicate_report_catalog(disabled_indexes: [], root_indexes: [0, 1])
      Dir.mktmpdir do |dir|
        executions_file = File.join(dir, "executions")
        roots = [File.join(dir, "first"), File.join(dir, "second")]
        FileUtils.mkdir_p(roots)

        %w[report Report].each_with_index do |pack_name, index|
          workflow_dir = File.join(roots[index], pack_name)
          FileUtils.mkdir_p(workflow_dir)
          label = index.zero? ? "first" : "second"
          source = +""
          source << "# r3x:disable duplicate test\n" if disabled_indexes.include?(index)
          source << <<~RUBY
            File.open(#{executions_file.inspect}, "a") { |file| file.write(#{label.inspect}) }

            module Workflows
              class Report < R3x::Workflow::Base
                trigger :manual, key: :#{label}

                def run
                  { "message" => #{label.inspect} }
                end
              end
            end
          RUBY
          File.write(File.join(workflow_dir, "workflow.rb"), source)
        end

        ENV["R3X_WORKFLOW_PATHS"] = roots.values_at(*root_indexes).join(File::PATH_SEPARATOR)
        yield executions_file
      end
    ensure
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
    end
  end
end

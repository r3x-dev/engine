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

    private

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
  end
end

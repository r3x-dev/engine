require "test_helper"

module R3x
  class WorkflowPackLoaderTest < ActiveSupport::TestCase
    setup do
      @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
      @legacy_workflow_dir = Rails.root.join("tmp/legacy_schema_workflow_#{SecureRandom.hex(4)}")
      R3x::Workflow::PackLoader.load!(force: true)
    end

    teardown do
      ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
      FileUtils.rm_rf(@legacy_workflow_dir) if @legacy_workflow_dir
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

    test "can run loaded workflow" do
      workflow_class = R3x::Workflow::Registry.fetch("test_workflow")
      result = workflow_class.new.run

      assert_equal true, result["test"]
      assert_equal "Test workflow executed successfully", result["message"]
    end

    test "logs loaded workflows with workflow tags" do
      output = capture_logged_output do
        R3x::Workflow::PackLoader.load!(force: true)
      end

      assert_includes output, "R3x::Workflow::PackLoader"
      assert_includes output, "r3x.workflow_key=test_workflow"
      assert_includes output, "Loaded workflow class=Workflows::TestWorkflow"
    end

    test "loads legacy workflows that still inherit from RubyLLM::Schema" do
      FileUtils.mkdir_p(@legacy_workflow_dir.join("legacy_schema"))
      File.write(@legacy_workflow_dir.join("legacy_schema/workflow.rb"), <<~RUBY)
        module Workflows
          class LegacySchema < R3x::Workflow::Base
            class OutputSchema < RubyLLM::Schema
              string :status
            end

            trigger :schedule, cron: "0 * * * *"

            def run
              { "status" => "ok" }
            end
          end
        end
      RUBY

      ENV["R3X_WORKFLOW_PATHS"] = [
        Rails.root.join("test/fixtures/workflows"),
        @legacy_workflow_dir
      ].join(File::PATH_SEPARATOR)

      assert_nothing_raised do
        R3x::Workflow::PackLoader.load!(force: true)
      end

      assert_equal Workflows::LegacySchema, R3x::Workflow::Registry.fetch("legacy_schema")
    end
  end
end

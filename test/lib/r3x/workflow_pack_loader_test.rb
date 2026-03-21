require "test_helper"

module R3x
  class WorkflowPackLoaderTest < ActiveSupport::TestCase
    setup do
      @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
      R3x::Workflow::PackLoader.load!(force: true)
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

    test "rejects workflow that accesses ENV directly" do
      Dir.mktmpdir do |dir|
        wf_dir = File.join(dir, "env_violation_wf")
        FileUtils.mkdir_p(wf_dir)
        File.write(File.join(wf_dir, "workflow.rb"), <<~RUBY)
          module Workflows
            class EnvViolationWf < R3x::Workflow::Base
              def run(ctx)
                { secret: ENV["MY_SECRET"] }
              end
            end
          end
        RUBY

        ENV["R3X_WORKFLOW_PATHS"] = wf_dir
        assert_raises(R3x::Workflow::Validator::ForbiddenAccessError) do
          R3x::Workflow::PackLoader.load!(force: true)
        end
      ensure
        ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
        R3x::Workflow::Registry.reset!
        R3x::Workflow::PackLoader.load!(force: true)
      end
    end

    test "rejects workflow that accesses R3x::Env directly" do
      Dir.mktmpdir do |dir|
        wf_dir = File.join(dir, "r3xenv_violation_wf")
        FileUtils.mkdir_p(wf_dir)
        File.write(File.join(wf_dir, "workflow.rb"), <<~RUBY)
          module Workflows
            class R3xenvViolationWf < R3x::Workflow::Base
              def run(ctx)
                { key: R3x::Env.fetch!("MY_KEY") }
              end
            end
          end
        RUBY

        ENV["R3X_WORKFLOW_PATHS"] = wf_dir
        assert_raises(R3x::Workflow::Validator::ForbiddenAccessError) do
          R3x::Workflow::PackLoader.load!(force: true)
        end
      ensure
        ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
        R3x::Workflow::Registry.reset!
        R3x::Workflow::PackLoader.load!(force: true)
      end
    end
  end
end

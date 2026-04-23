require "test_helper"

class DevelopmentEnvironmentTest < ActiveSupport::TestCase
  test "routes active job logs through the workflow logger in development config" do
    source = Rails.root.join("config/environments/development.rb").read

    assert_includes source, "config.active_job.logger = R3x::WorkflowLog.build_logger(env: Rails.env)"
    assert_includes source, "config.solid_queue.logger = config.logger"
    refute_includes source, "config.x.workflow_execution_logger"
  end
end

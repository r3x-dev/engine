require "test_helper"

class ProductionEnvironmentTest < ActiveSupport::TestCase
  test "does not route active job logs through the workflow file logger in production config" do
    source = Rails.root.join("config/environments/production.rb").read

    refute_includes source, "config.active_job.logger = R3x::WorkflowLog.build_logger(env: Rails.env)"
  end
end

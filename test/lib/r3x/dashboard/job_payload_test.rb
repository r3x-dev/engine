require "test_helper"

module R3x
  module Dashboard
    class JobPayloadTest < ActiveSupport::TestCase
      test "extracts trigger payload from serialized workflow job arguments" do
        raw_arguments = DashboardJobRows.serialized_job_payload(
          job_class_name: R3x::TestSupport::DashboardWorkflowJob.name,
          arguments: [ "schedule:abc123", { trigger_payload: { "id" => "42" } } ]
        )
        payload = JobPayload.new(raw_arguments)

        assert_equal({ "id" => "42" }, payload.trigger_payload)
      end

      test "extracts trigger payload from legacy run workflow arguments" do
        raw_arguments = DashboardJobRows.serialized_job_payload(
          job_class_name: "R3x::RunWorkflowJob",
          arguments: [ "test_workflow", { "trigger_key" => "manual:legacy", "trigger_payload" => { "id" => "99" } } ]
        )
        payload = JobPayload.new(raw_arguments)

        assert_equal({ "id" => "99" }, payload.trigger_payload)
      end
    end
  end
end

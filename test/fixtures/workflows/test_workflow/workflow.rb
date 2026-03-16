module Workflows
  class TestWorkflow < R3x::Workflow
    trigger :schedule, cron: "0 * * * *"

    def run(ctx)
      {
        "test" => true,
        "message" => "Test workflow executed successfully"
      }
    end
  end
end

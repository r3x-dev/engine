module R3x
  module Dashboard
    class WorkflowRunLogsController < ApplicationController
      def show
        @run = Workflow::Runs.new.find!(params[:workflow_run_id])
        @logs = Logs.new.run_logs(@run)

        render partial: "r3x/dashboard/workflow_runs/logs_panel", locals: { run: @run, logs: @logs }, layout: false
      end
    end
  end
end

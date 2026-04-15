module R3x
  module Dashboard
    class WorkflowsController < ApplicationController
      def index
        @workflows = WorkflowSummaries.new.all
      end

      def show
        @workflow = WorkflowSummaries.new.find!(params[:workflow_key])
        @runs = WorkflowRuns.new(workflow_key: params[:workflow_key], limit: 25).all
        @latest_failure = WorkflowRuns.new(workflow_key: params[:workflow_key], status: "failed", limit: 1).all.first
        @logs = Logs.new.workflow_logs(params[:workflow_key]) if logs_requested?
      end

      def run_trigger
        WorkflowRunEnqueuer.new(
          workflow_key: params[:workflow_key],
          trigger_key: params[:trigger_key]
        ).enqueue!

        redirect_to workflow_path(params[:workflow_key]), notice: "Queued a new run for #{params[:workflow_key].titleize}."
      end
    end
  end
end

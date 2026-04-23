module R3x
  module Dashboard
    class WorkflowRunsController < ApplicationController
      def index
        @workflow_filter = params[:workflow].presence
        @status_filter = params[:status].presence
        @workflow_options = Workflow::Catalog.new.all
        @statuses = Workflow::Runs.statuses
        @runs = Workflow::Runs.new(workflow_key: @workflow_filter, status: @status_filter).all
      end

      def show
        @run = Workflow::Runs.new.find!(params[:id])
        @logs = Logs.new.run_logs(@run) if logs_configured?
      end
    end
  end
end

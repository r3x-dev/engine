module R3x
  module Dashboard
    class WorkflowRunsController < ApplicationController
      def index
        @workflow_filter = params[:workflow].presence
        @status_filter = params[:status].presence
        @workflow_options = WorkflowCatalog.new.all
        @statuses = WorkflowRuns.statuses
        @runs = WorkflowRuns.new(workflow_key: @workflow_filter, status: @status_filter).all
      end

      def show
        @run = WorkflowRuns.new.find!(params[:id])
      end
    end
  end
end

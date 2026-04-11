module R3x
  module Dashboard
    class WorkflowsController < ApplicationController
      def index
        @workflows = WorkflowSummaries.new.all
      end

      def show
        @workflow = WorkflowSummaries.new.find!(params[:workflow_key])
        @runs = WorkflowRuns.new(workflow_key: params[:workflow_key], limit: 25).all
      end
    end
  end
end

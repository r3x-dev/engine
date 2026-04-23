module R3x
  module Dashboard
    class WorkflowsController < ApplicationController
      def index
        summaries = Workflow::Summaries.new(sort: params[:sort], direction: params[:direction])

        @direction = summaries.direction
        @sort = summaries.sort
        @workflows = summaries.all
      end

      def show
        @workflow = Workflow::Summaries.new.find!(params[:workflow_key])
        @runs = Workflow::Runs.new(workflow_key: params[:workflow_key], limit: 10).all
        @latest_failure = Workflow::Runs.new(workflow_key: params[:workflow_key], status: "failed", limit: 1).all.first
      end

      def run_trigger
        Workflow::RunEnqueuer.new(
          workflow_key: params[:workflow_key],
          trigger_key: params[:trigger_key]
        ).enqueue!

        redirect_to workflow_path(params[:workflow_key]), notice: "Queued a new run for #{params[:workflow_key].titleize}."
      rescue ActiveRecord::RecordNotFound, KeyError
        head :not_found
      end
    end
  end
end

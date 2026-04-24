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
        run = Workflow::RunEnqueuer.new(
          workflow_key: params[:workflow_key],
          trigger_key: params[:trigger_key]
        ).enqueue!

        if run
          redirect_to workflow_run_path(run), notice: "Queued a new run for #{params[:workflow_key].titleize}."
        else
          redirect_to workflow_path(params[:workflow_key]), notice: "Queued a new run for #{params[:workflow_key].titleize}."
        end
      rescue ActiveRecord::RecordNotFound, KeyError
        head :not_found
      end
    end
  end
end

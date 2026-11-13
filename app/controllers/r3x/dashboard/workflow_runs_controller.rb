# frozen_string_literal: true

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

        respond_to do |format|
          format.html { @logs = Logs.run_logs(@run) if Logs.enabled? }
          format.json { render json: { status: @run.fetch(:status) } }
        end
      end

      def create
        request = Workflow::RunEnqueuer.new(workflow_key: params[:workflow_key], trigger_key: params[:trigger_key]).enqueue!

        redirect_to workflow_run_request_path(workflow_key: params[:workflow_key], id: request.id), status: :see_other
      end
    end
  end
end

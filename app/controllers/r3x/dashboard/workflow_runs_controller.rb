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
        @logs = Logs.new.run_logs(@run) if logs_configured?
      end

      def create
        run = Workflow::RunEnqueuer.new(workflow_key: params[:workflow_key], trigger_key: params[:trigger_key]).enqueue!

        redirect_to workflow_run_path(run), notice: "Queued a new run for #{params[:workflow_key].titleize}."
      rescue ActiveRecord::RecordNotFound, KeyError
        head :not_found
      end
    end
  end
end

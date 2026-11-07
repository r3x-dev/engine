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
        @logs = Logs.run_logs(@run) if Logs.enabled?
      end

      def create
        Workflow::RunEnqueuer.new(workflow_key: params[:workflow_key], trigger_key: params[:trigger_key]).enqueue!

        redirect_to workflow_path(params[:workflow_key]), notice: "Queued a run request for #{params[:workflow_key].titleize}."
      end
    end
  end
end

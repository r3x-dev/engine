# frozen_string_literal: true

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
    end
  end
end

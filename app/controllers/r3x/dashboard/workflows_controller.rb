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
        class_names = Workflow::Catalog.new.class_names_for(params[:workflow_key])
        @enqueue_requests = ::Dashboard::EnqueueRequest.for_workflow(class_names)
          .with_execution_associations.order(created_at: :desc, id: :desc).limit(10)
      end
    end
  end
end

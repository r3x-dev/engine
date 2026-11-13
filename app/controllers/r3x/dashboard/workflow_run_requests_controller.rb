# frozen_string_literal: true

module R3x
  module Dashboard
    class WorkflowRunRequestsController < ApplicationController
      def show
        catalog = Workflow::Catalog.new
        @workflow = catalog.find!(params[:workflow_key])
        @request = ::Dashboard::EnqueueRequest.for_workflow(catalog.class_names_for(params[:workflow_key]))
          .with_execution_associations.find(params[:id])
        run = @request.workflow_run

        respond_to do |format|
          format.html { redirect_to workflow_run_path(run.id) if run }
          format.json do
            state = { status: @request.status }
            state[:run_url] = workflow_run_path(run.id) if run
            render json: state
          end
        end
      end
    end
  end
end

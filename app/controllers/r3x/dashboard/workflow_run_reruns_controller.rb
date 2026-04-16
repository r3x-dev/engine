module R3x
  module Dashboard
    class WorkflowRunRerunsController < ApplicationController
      def create
        run = WorkflowRuns.new.find!(params[:workflow_run_id])
        return head :not_found unless rerunnable?(run)

        WorkflowRunRerunner.new(run: run).enqueue!

        redirect_to workflow_run_path(run[:job_id]), notice: "Queued rerun for #{run[:workflow_title]}."
      end

      private
        def rerunnable?(run)
          run[:known_workflow] && %w[failed finished].include?(run[:status].to_s)
        end
    end
  end
end

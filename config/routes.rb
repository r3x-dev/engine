Rails.application.routes.draw do
  mount MissionControl::Jobs::Engine, at: "/ops/jobs"

  scope module: "r3x/dashboard" do
    root "workflows#index"

    resources :workflows, only: %i[ index show ], param: :workflow_key do
      post :run_trigger, on: :member
    end
    resources :workflow_runs, only: %i[ index show ], path: "workflow-runs" do
      resource :logs, only: :show, controller: "workflow_run_logs"
      resource :rerun, only: :create, controller: "workflow_run_reruns"
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check
end

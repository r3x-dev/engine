Rails.application.routes.draw do
  mount MissionControl::Jobs::Engine, at: "/ops/jobs"

  scope module: "r3x/dashboard" do
    root "workflows#index"

    resources :workflows, only: %i[ index show ], param: :workflow_key
    resources :workflow_runs, only: :index, path: "workflow-runs"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check
end

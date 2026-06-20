# frozen_string_literal: true

Rails.application.routes.draw do
  mount MissionControl::Jobs::Engine, at: "/ops/jobs"

  scope module: "r3x/dashboard" do
    root "overview#index"

    resources :workflows, only: %i[ index show ], param: :workflow_key do
      post :runs, on: :member, to: "workflow_runs#create", as: :runs
    end
    resources :workflow_runs, only: %i[ index show ], path: "workflow-runs" do
      resource :logs, only: :show, controller: "workflow_run_logs"
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check
end

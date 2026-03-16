Rails.application.routes.draw do
  # Mount Mission Control Jobs dashboard
  mount MissionControl::Jobs::Engine, at: "/jobs"

  # Root redirects to Mission Control Jobs dashboard (using unnamed route to hide from Mission Control)
  get "/", to: redirect("/jobs")

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check
end

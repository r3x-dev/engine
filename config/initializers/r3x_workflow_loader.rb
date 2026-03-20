Rails.application.config.after_initialize do
  R3x::Workflow::PackLoader.load!
end

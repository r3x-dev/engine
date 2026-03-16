Rails.application.config.after_initialize do
  R3x::WorkflowPackLoader.load!
end

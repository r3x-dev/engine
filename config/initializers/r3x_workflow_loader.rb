require Rails.root.join("lib/r3x/workflow_pack_loader")

Rails.application.config.after_initialize do
  R3x::WorkflowPackLoader.load!
end

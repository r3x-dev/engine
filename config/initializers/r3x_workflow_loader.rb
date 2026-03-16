require Rails.root.join("lib/r3x/workflow_pack_loader")
require Rails.root.join("lib/r3x/workflow")
require Rails.root.join("lib/r3x/recurring_tasks_config")

# Validators for triggers and other components
Dir[Rails.root.join("lib/r3x/validators/*.rb")].each { |f| require f }

Rails.application.config.after_initialize do
  R3x::WorkflowPackLoader.load!
end

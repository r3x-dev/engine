Rails.application.config.after_initialize do
  vault_path = ENV["R3X_VAULT_SECRETS_PATH"].presence
  R3x::Env.load_from_vault(vault_path) if vault_path
end

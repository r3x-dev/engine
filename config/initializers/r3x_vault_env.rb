Rails.application.config.after_initialize do
  next if R3x::Env.fetch_boolean("R3X_SKIP_VAULT_ENV_LOAD")

  vault_path = R3x::Env.fetch("R3X_VAULT_SECRETS_PATH")
  R3x::Env.load_from_vault(vault_path) if vault_path
end

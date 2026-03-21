Rails.application.config.before_initialize do
  require "r3x/env"
  vault_path = ENV["R3X_VAULT_SECRETS_PATH"].presence
  R3x::Env.load_from_vault(vault_path) if vault_path
end

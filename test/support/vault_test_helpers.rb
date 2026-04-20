require "base64"
require "tempfile"

module VaultTestHelpers
  ENV_KEYS = [
    "R3X_VAULT_ADDR",
    "R3X_VAULT_TOKEN",
    "R3X_VAULT_SECRETS_PATH",
    "R3X_VAULT_AUTH_METHOD",
    "R3X_VAULT_KUBERNETES_ROLE",
    "R3X_VAULT_KUBERNETES_AUTH_PATH",
    "R3X_VAULT_KUBERNETES_TOKEN_PATH",
    "GEMINI_API_KEY_TEST"
  ].freeze

  def self.included(base)
    base.setup do
      @original_vault_env = snapshot_vault_env
      reset_vault_singleton
    end

    base.teardown do
      restore_vault_env
      WebMock.reset!
      reset_vault_singleton
    end
  end

  private

  def snapshot_vault_env
    ENV_KEYS.index_with { |key| ENV[key] }
  end

  def restore_vault_env
    @original_vault_env.each do |key, value|
      ENV[key] = value
    end
  end

  def with_service_account_token(token)
    file = Tempfile.new("vault-kubernetes-token")
    file.write(token)
    file.flush

    yield file.path
  ensure
    file&.close!
  end

  def kubernetes_jwt(namespace:, service_account_name:)
    encode_jwt_payload({
      "sub" => "system:serviceaccount:#{namespace}:#{service_account_name}",
      "kubernetes.io" => {
        "namespace" => namespace,
        "serviceaccount" => {
          "name" => service_account_name
        }
      }
    })
  end

  def encode_jwt_payload(payload)
    [ "header", urlsafe_base64(payload.to_json), "signature" ].join(".")
  end

  def urlsafe_base64(value)
    Base64.urlsafe_encode64(value, padding: false)
  end

  def reset_vault_singleton
    R3x::Client::HashiCorpVault.instance_variable_set(:@singleton__instance__, nil)
  end
end

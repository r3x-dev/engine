module R3x
  module Client
    class HashiCorpVault
      class Config
        DEFAULT_KUBERNETES_AUTH_PATH = "auth/kubernetes"
        DEFAULT_KUBERNETES_TOKEN_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        REQUIRED_AUTH_ENV_KEYS = {
          token: "R3X_VAULT_TOKEN",
          kubernetes: "R3X_VAULT_KUBERNETES_ROLE"
        }.freeze

        def self.configured?
          return false unless R3x::Env.present?("R3X_VAULT_ADDR")

          R3x::Env.present?(required_auth_env_key)
        end

        def self.validate!
          R3x::Env.fetch!(required_auth_env_key)
        end

        def self.parsed_auth_method
          case R3x::Env.fetch("R3X_VAULT_AUTH_METHOD")
          when nil, "", "token"
            :token
          when "kubernetes"
            :kubernetes
          else
            :unsupported
          end
        end

        def self.auth_method
          case parsed_auth_method
          when :token
            :token
          when :kubernetes
            :kubernetes
          else
            raise ArgumentError, "Unsupported Vault auth method: #{R3x::Env.fetch("R3X_VAULT_AUTH_METHOD").inspect}"
          end
        end

        def self.required_auth_env_key
          REQUIRED_AUTH_ENV_KEYS.fetch(auth_method)
        end

        def initialize
          @vault_addr = R3x::Env.fetch!("R3X_VAULT_ADDR")
          self.class.validate!
        end

        attr_reader :vault_addr

        def auth_method
          @auth_method ||= self.class.auth_method
        end

        def token
          R3x::Env.fetch!("R3X_VAULT_TOKEN")
        end

        def kubernetes_role
          R3x::Env.fetch!("R3X_VAULT_KUBERNETES_ROLE")
        end

        def kubernetes_auth_path
          R3x::Env.fetch("R3X_VAULT_KUBERNETES_AUTH_PATH") || DEFAULT_KUBERNETES_AUTH_PATH
        end

        def kubernetes_token_path
          R3x::Env.fetch("R3X_VAULT_KUBERNETES_TOKEN_PATH") || DEFAULT_KUBERNETES_TOKEN_PATH
        end
      end
    end
  end
end

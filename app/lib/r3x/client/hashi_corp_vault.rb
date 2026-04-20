require "base64"
require "singleton"

module R3x
  module Client
    class HashiCorpVault
      include Singleton
      extend R3x::Concerns::Logger

      def self.read(path)
        instance.read(path)
      end

      def self.lookup_self
        instance.lookup_self
      end

      def self.renew_self
        instance.renew_self
      end

      def self.capabilities_self(paths)
        instance.capabilities_self(paths)
      end

      def self.diagnose(path: R3x::Env.fetch!("R3X_VAULT_SECRETS_PATH"))
        instance.diagnose(path: path)
      end

      def self.configured?
        return false unless R3x::Env.present?("R3X_VAULT_ADDR")

        case configured_auth_method
        when :token
          token_configured?
        when :kubernetes
          kubernetes_auth_configured?
        else
          raise ArgumentError, "Unsupported Vault auth method: #{R3x::Env.fetch("R3X_VAULT_AUTH_METHOD").inspect}"
        end
      end

      def self.token_configured?
        R3x::Env.present?("R3X_VAULT_TOKEN")
      end

      def self.kubernetes_auth_configured?
        R3x::Env.fetch("R3X_VAULT_AUTH_METHOD") == "kubernetes" &&
          R3x::Env.present?("R3X_VAULT_KUBERNETES_ROLE")
      end

      def self.configured_auth_method
        case R3x::Env.fetch("R3X_VAULT_AUTH_METHOD")
        when nil, "", "token"
          :token
        when "kubernetes"
          :kubernetes
        else
          :unsupported
        end
      end

      def read(path)
        response = connection.get("v1/#{path}")

        raise_request_error(response) unless response.success?

        secrets = response.body.is_a?(Hash) && response.body.dig("data", "data")

        unless secrets.is_a?(Hash) && secrets.present?
          raise "Vault response missing KV v2 data at data.data"
        end

        secrets.transform_keys(&:to_s)
      end

      def lookup_self
        response = connection.get("v1/auth/token/lookup-self")

        raise_request_error(response) unless response.success?

        data = response.body.is_a?(Hash) && response.body["data"]
        raise "Vault response missing token lookup data" unless data.is_a?(Hash)

        data
      end

      def renew_self
        response = connection.post("v1/auth/token/renew-self")

        raise_request_error(response) unless response.success?

        auth = response.body.is_a?(Hash) && response.body["auth"]
        raise "Vault response missing token renewal auth data" unless auth.is_a?(Hash)

        auth
      end

      def capabilities_self(paths)
        response = connection.post("v1/sys/capabilities-self", { paths: Array(paths) })

        raise_request_error(response) unless response.success?

        raise "Vault response missing capabilities data" unless response.body.is_a?(Hash)

        response.body
      end

      def diagnose(path:)
        capabilities_paths = [ path, "auth/token/lookup-self", "auth/token/renew-self" ]
        capabilities = capabilities_self(capabilities_paths)
        token = lookup_summary

        {
          auth_method: auth_method,
          vault_addr: vault_addr,
          secret_path: path,
          token: token,
          capabilities: capabilities,
          renewal: renewal_supported?(capabilities, token) ? renewal_summary : nil,
          secret: {
            keys: read(path).keys.sort
          }
        }
      end

      private

      def initialize
        @vault_addr = R3x::Env.fetch!("R3X_VAULT_ADDR")
      end

      attr_reader :vault_addr

      def connection
        @connection ||= build_connection(token: vault_token)
      end

      def unauthenticated_connection
        @unauthenticated_connection ||= build_connection
      end

      def build_connection(token: nil)
        Faraday.new(url: vault_addr) do |f|
          f.request :json
          f.response :json
          f.headers["X-Vault-Token"] = token if token.present?
        end
      end

      def vault_token
        @vault_token ||= case auth_method
        when :token
          R3x::Env.fetch!("R3X_VAULT_TOKEN")
        when :kubernetes
          login_with_kubernetes
        else
          raise ArgumentError, "Unsupported Vault auth method: #{auth_method.inspect}"
        end
      end

      def auth_method
        @auth_method ||= case self.class.configured_auth_method
        when :token
          :token
        when :kubernetes
          :kubernetes
        else
          raise ArgumentError, "Unsupported Vault auth method: #{R3x::Env.fetch("R3X_VAULT_AUTH_METHOD").inspect}"
        end
      end

      def login_with_kubernetes
        response = unauthenticated_connection.post("v1/#{kubernetes_auth_path}/login", {
          role: kubernetes_role,
          jwt: kubernetes_service_account_token
        })

        raise_kubernetes_login_error(response) unless response.success?

        auth = response.body.is_a?(Hash) && response.body["auth"]
        raise "Vault response missing kubernetes auth data" unless auth.is_a?(Hash)

        client_token = auth["client_token"].presence
        raise "Vault response missing kubernetes client token" if client_token.blank?

        client_token
      end

      def kubernetes_role
        R3x::Env.fetch!("R3X_VAULT_KUBERNETES_ROLE")
      end

      def kubernetes_auth_path
        R3x::Env.fetch("R3X_VAULT_KUBERNETES_AUTH_PATH") || "auth/kubernetes"
      end

      def kubernetes_token_path
        R3x::Env.fetch("R3X_VAULT_KUBERNETES_TOKEN_PATH") || "/var/run/secrets/kubernetes.io/serviceaccount/token"
      end

      def kubernetes_service_account_token
        token = File.read(kubernetes_token_path).strip
        raise "Vault Kubernetes service account token is blank" if token.blank?

        token
      rescue Errno::ENOENT => e
        raise "Vault Kubernetes service account token not found at #{kubernetes_token_path}: #{e.message}"
      end

      def lookup_summary
        lookup_self.slice(
          "display_name",
          "policies",
          "ttl",
          "renewable",
          "period",
          "explicit_max_ttl"
        )
      end

      def renewal_summary
        renew_self.slice(
          "lease_duration",
          "renewable",
          "policies"
        )
      end

      def renewal_supported?(capabilities, token)
        capabilities.fetch("auth/token/renew-self", []).include?("update") && token["renewable"]
      end

      def raise_kubernetes_login_error(response)
        identity = kubernetes_service_account_identity
        scope = if identity
          " (#{identity.fetch(:namespace)}/#{identity.fetch(:service_account_name)})"
        end

        raise "Vault Kubernetes auth login failed with status #{response.status}: #{request_errors(response)}. " \
          "Vault could not exchange the Kubernetes service account token for a Vault token. " \
          "Check the auth/kubernetes backend configuration (reviewer JWT, Kubernetes host, CA certificate, and issuer settings) " \
          "and verify that role #{kubernetes_role.inspect} is bound to the expected service account and namespace#{scope}."
      end

      def kubernetes_service_account_identity
        claims = kubernetes_service_account_claims

        namespace = claims.dig("kubernetes.io", "namespace")
        service_account_name = claims.dig("kubernetes.io", "serviceaccount", "name")

        return if namespace.blank? || service_account_name.blank?

        {
          namespace: namespace,
          service_account_name: service_account_name
        }
      rescue ArgumentError, MultiJson::ParseError
        nil
      end

      def kubernetes_service_account_claims
        _header, payload, _signature = kubernetes_service_account_token.split(".", 3)
        raise ArgumentError, "JWT payload missing" if payload.blank?

        MultiJson.load(Base64.urlsafe_decode64(pad_base64(payload)))
      end

      def pad_base64(value)
        value.ljust((value.length + 3) & ~3, "=")
      end

      def request_errors(response)
        response.body.is_a?(Hash) ? response.body["errors"] : response.body
      end

      def raise_request_error(response)
        raise "Vault request failed with status #{response.status}: #{request_errors(response)}"
      end
    end
  end
end

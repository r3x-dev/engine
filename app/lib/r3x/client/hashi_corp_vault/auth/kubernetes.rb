require "base64"

module R3x
  module Client
    class HashiCorpVault
      module Auth
        class Kubernetes
          def initialize(config:, connection_builder:)
            @config = config
            @connection_builder = connection_builder
          end

          def client_token
            response = unauthenticated_connection.post("v1/#{config.kubernetes_auth_path}/login", {
              role: config.kubernetes_role,
              jwt: service_account_token
            })

            raise_login_error(response) unless response.success?

            auth = response.body.is_a?(Hash) && response.body["auth"]
            raise "Vault response missing kubernetes auth data" unless auth.is_a?(Hash)

            client_token = auth["client_token"].presence
            raise "Vault response missing kubernetes client token" if client_token.blank?

            client_token
          end

          private

          attr_reader :config, :connection_builder

          def unauthenticated_connection
            @unauthenticated_connection ||= connection_builder.call
          end

          def service_account_token
            token = File.read(config.kubernetes_token_path).strip
            raise "Vault Kubernetes service account token is blank" if token.blank?

            token
          rescue Errno::ENOENT => e
            raise "Vault Kubernetes service account token not found at #{config.kubernetes_token_path}: #{e.message}"
          end

          def raise_login_error(response)
            identity = service_account_identity
            scope = if identity
              " (#{identity.fetch(:namespace)}/#{identity.fetch(:service_account_name)})"
            end

            raise "Vault Kubernetes auth login failed with status #{response.status}: #{request_errors(response)}. " \
              "Vault could not exchange the Kubernetes service account token for a Vault token. " \
              "Check the auth/kubernetes backend configuration (reviewer JWT, Kubernetes host, CA certificate, and issuer settings) " \
              "and verify that role #{config.kubernetes_role.inspect} is bound to the expected service account and namespace#{scope}."
          end

          def service_account_identity
            claims = service_account_claims

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

          def service_account_claims
            _header, payload, _signature = service_account_token.split(".", 3)
            raise ArgumentError, "JWT payload missing" if payload.blank?

            MultiJson.load(Base64.urlsafe_decode64(pad_base64(payload)))
          end

          def pad_base64(value)
            value.ljust((value.length + 3) & ~3, "=")
          end

          def request_errors(response)
            response.body.is_a?(Hash) ? response.body["errors"] : response.body
          end
        end
      end
    end
  end
end

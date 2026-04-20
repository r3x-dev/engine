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
        R3x::Env.present?("R3X_VAULT_ADDR") && R3x::Env.present?("R3X_VAULT_TOKEN")
      end

      def read(path)
        response = connection.get("v1/#{path}")

        raise_request_error(response) unless response.success?

        secrets = response.body.is_a?(Hash) && response.body.dig("data", "data")

        unless secrets.is_a?(Hash) && secrets.present?
          raise RuntimeError, "Vault response missing KV v2 data at data.data"
        end

        secrets.transform_keys(&:to_s)
      end

      def lookup_self
        response = connection.get("v1/auth/token/lookup-self")

        raise_request_error(response) unless response.success?

        data = response.body.is_a?(Hash) && response.body["data"]
        raise RuntimeError, "Vault response missing token lookup data" unless data.is_a?(Hash)

        data
      end

      def renew_self
        response = connection.post("v1/auth/token/renew-self")

        raise_request_error(response) unless response.success?

        auth = response.body.is_a?(Hash) && response.body["auth"]
        raise RuntimeError, "Vault response missing token renewal auth data" unless auth.is_a?(Hash)

        auth
      end

      def capabilities_self(paths)
        response = connection.post("v1/sys/capabilities-self", { paths: Array(paths) })

        raise_request_error(response) unless response.success?

        raise RuntimeError, "Vault response missing capabilities data" unless response.body.is_a?(Hash)

        response.body
      end

      def diagnose(path:)
        {
          vault_addr: vault_addr,
          secret_path: path,
          token: lookup_summary,
          capabilities: capabilities_self([ path, "auth/token/lookup-self", "auth/token/renew-self" ]),
          renewal: renewal_summary,
          secret: {
            keys: read(path).keys.sort
          }
        }
      end

      private

      def initialize
        @vault_addr = R3x::Env.fetch!("R3X_VAULT_ADDR")
        @vault_token = R3x::Env.fetch!("R3X_VAULT_TOKEN")
      end

      attr_reader :vault_addr, :vault_token

      def connection
        @connection ||= Faraday.new(url: vault_addr) do |f|
          f.request :json
          f.response :json
          f.headers["X-Vault-Token"] = vault_token
        end
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

      def raise_request_error(response)
        errors = response.body.is_a?(Hash) ? response.body["errors"] : response.body

        raise RuntimeError, "Vault request failed with status #{response.status}: #{errors}"
      end
    end
  end
end

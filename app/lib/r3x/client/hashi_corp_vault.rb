require "singleton"

module R3x
  module Client
    class HashiCorpVault
      include Singleton

      def self.read(path)
        instance.read(path)
      end

      def self.token_valid?
        instance.token_valid?
      end

      def initialize
        @vault_addr = R3x::Env.fetch("VAULT_ADDR")
        @vault_token = R3x::Env.fetch("VAULT_TOKEN")
      end

      def read(path)
        response = connection.get("v1/#{path}")

        raise RuntimeError, "Vault request failed with status #{response.status}: #{response.body["errors"]}" unless response.success?

        secrets = response.body.is_a?(Hash) && response.body.dig("data", "data")

        unless secrets.is_a?(Hash) && secrets.present?
          raise RuntimeError, "Vault response missing KV v2 data at data.data"
        end

        secrets.transform_keys(&:to_s)
      end

      def token_valid?
        connection.get("v1/auth/token/lookup-self").success?
      rescue StandardError
        false
      end

      private

      attr_reader :vault_addr, :vault_token

      def connection
        @connection ||= Faraday.new(url: vault_addr) do |f|
          f.response :json
          f.headers["X-Vault-Token"] = vault_token
        end
      end
    end
  end
end

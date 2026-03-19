require "singleton"

module R3x
  module Client
    class HashiCorpVault
      include Singleton

      def self.read(path)
        instance.read(path)
      end

      def initialize
        @vault_addr = ENV["VAULT_ADDR"].presence || raise(ArgumentError, "Missing VAULT_ADDR")
        @vault_token = ENV["VAULT_TOKEN"].presence || raise(ArgumentError, "Missing VAULT_TOKEN")
      end

      def read(path)
        response = connection.get("/v1/#{path}")

        raise RuntimeError, "Vault request failed with status #{response.status}: #{response.body["errors"]}" unless response.success?

        secrets = response.body.is_a?(Hash) && response.body.dig("data", "data")

        unless secrets.is_a?(Hash)
          raise RuntimeError, "Vault response missing KV v2 data at data.data"
        end

        secrets.transform_keys(&:to_s)
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

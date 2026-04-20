require "singleton"

module R3x
  module Client
    class HashiCorpVault
      include Singleton

      def self.read(path)
        instance.read(path)
      end

      def self.lookup_self
        instance.lookup_self
      end

      def self.capabilities_self(paths)
        instance.capabilities_self(paths)
      end

      def self.diagnose(path: R3x::Env.fetch!("R3X_VAULT_SECRETS_PATH"))
        instance.diagnose(path: path)
      end

      def self.configured?
        Config.configured?
      end

      def self.validate_auth_configuration!
        Config.validate!
      end

      def read(path)
        body = get("v1/#{path}")
        secrets = body.is_a?(Hash) && body.dig("data", "data")

        unless secrets.is_a?(Hash) && secrets.present?
          raise "Vault response missing KV v2 data at data.data"
        end

        secrets.transform_keys(&:to_s)
      end

      def lookup_self
        data = get("v1/auth/token/lookup-self")["data"]
        raise "Vault response missing token lookup data" unless data.is_a?(Hash)

        data
      end

      def capabilities_self(paths)
        post("v1/sys/capabilities-self", { paths: Array(paths) }).tap do |body|
          raise "Vault response missing capabilities data" unless body.is_a?(Hash)
        end
      end

      def diagnose(path:)
        capabilities_paths = [ path, "auth/token/lookup-self" ]
        capabilities = capabilities_self(capabilities_paths)
        token = lookup_summary

        {
          auth_method: auth_method,
          vault_addr: config.vault_addr,
          secret_path: path,
          token: token,
          capabilities: capabilities,
          secret: {
            keys: read(path).keys.sort
          }
        }
      end

      private

      def initialize
        @config = Config.new
      end

      attr_reader :config

      def connection
        @connection ||= build_connection(token: vault_token)
      end

      def build_connection(token: nil)
        Faraday.new(url: config.vault_addr) do |f|
          f.request :json
          f.response :json
          f.headers["X-Vault-Token"] = token if token.present?
        end
      end

      def vault_token
        @vault_token ||= auth.client_token
      end

      def auth_method
        config.auth_method
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

      def auth
        @auth ||= Auth.build(
          config: config,
          connection_builder: -> { build_connection }
        )
      end

      def get(path)
        request(:get, path)
      end

      def post(path, body)
        request(:post, path, body)
      end

      def request(method, path, body = nil)
        response = case method
        when :get
          connection.get(path)
        when :post
          connection.post(path, body)
        else
          raise ArgumentError, "Unsupported Vault HTTP method: #{method.inspect}"
        end

        raise_request_error(response) unless response.success?
        response.body
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

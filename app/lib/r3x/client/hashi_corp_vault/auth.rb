module R3x
  module Client
    class HashiCorpVault
      module Auth
        def self.build(config:, connection_builder:)
          case config.auth_method
          when :token
            Token.new(config: config)
          when :kubernetes
            Kubernetes.new(config: config, connection_builder: connection_builder)
          else
            raise ArgumentError, "Unsupported Vault auth method: #{config.auth_method.inspect}"
          end
        end
      end
    end
  end
end

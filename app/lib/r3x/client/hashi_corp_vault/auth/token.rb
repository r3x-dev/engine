module R3x
  module Client
    class HashiCorpVault
      module Auth
        class Token
          def initialize(config:)
            @config = config
          end

          def client_token
            config.token
          end

          private

          attr_reader :config
        end
      end
    end
  end
end

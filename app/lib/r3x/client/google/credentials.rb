# frozen_string_literal: true

module R3x
  module Client
    module Google
      module Credentials
        def self.from_env(credentials_env)
          MultiJson.load(R3x::Env.secure_fetch(credentials_env, prefix: "GOOGLE_CREDENTIALS_"))
        end
      end
    end
  end
end

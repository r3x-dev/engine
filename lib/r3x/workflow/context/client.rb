module R3x
  module Workflow
    class Context
      module Client
        extend self

        def http(verify_ssl: true, timeout: 10)
          R3x::Client::Http.new(verify_ssl: verify_ssl, timeout: timeout)
        end

        def prometheus
          R3x::Client::Prometheus.new
        end

        def apify(api_key_env:)
          R3x::Client::Apify.new(api_key: R3x::Env.secure_fetch(api_key_env, prefix: "APIFY_API_KEY"))
        end

        def llm(api_key_env:)
          R3x::Client::Llm.new(
            api_key: R3x::Env.secure_fetch(api_key_env, prefix: /\A[A-Z]+_API_KEY_[A-Z0-9_]+\z/),
            config_api_key_attr: "#{api_key_env.split("_").first.downcase}_api_key"
          )
        end

        def google_sheets(spreadsheet_id:, credentials_env:)
          R3x::Client::GoogleSheets.new(
            spreadsheet_id: spreadsheet_id,
            credentials_env: credentials_env
          )
        end

        def gmail(credentials_env:)
          R3x::Client::Google::Gmail.new(credentials_env: credentials_env)
        end

        def discord(webhook_url:)
          R3x::Client::Discord::Webhook.new(webhook_url: webhook_url)
        end
      end
    end
  end
end

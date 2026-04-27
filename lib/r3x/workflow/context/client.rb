module R3x
  module Workflow
    class Context
      module Client
        extend self

        def http(verify_ssl: true, timeout: 10)
          R3x::Client::Http.new(verify_ssl: verify_ssl, timeout: timeout)
        end

        def prometheus(url_env: "PROMETHEUS_URL")
          R3x::Client::Prometheus.new(url_env: url_env)
        end

        def apify(api_key_env:)
          R3x::Client::Apify.new(api_key: R3x::Env.secure_fetch(api_key_env, prefix: "APIFY_API_KEY"))
        end

        def llm(api_key_env:, max_retries: nil, retry_interval: nil, retry_backoff_factor: nil)
          R3x::Client::Llm.new(
            api_key: R3x::Env.secure_fetch(api_key_env, prefix: /\A[A-Z]+_API_KEY_[A-Z0-9_]+\z/),
            config_api_key_attr: "#{api_key_env.split("_").first.downcase}_api_key",
            max_retries: max_retries,
            retry_interval: retry_interval,
            retry_backoff_factor: retry_backoff_factor
          )
        end

        def google_sheets(spreadsheet_id:, project:)
          R3x::Client::GoogleSheets.new(
            spreadsheet_id: spreadsheet_id,
            project: project
          )
        end

        def gmail(project:)
          R3x::Client::Google::Gmail.new(project: project)
        end

        def ocr(api_key_env:)
          R3x::Client::Ocr.new(api_key_env: api_key_env)
        end

        def google_translate(project:)
          R3x::Client::Google::Translate.new(project: project)
        end

        def discord(webhook_url_env:)
          R3x::Client::Discord.new(webhook_url_env: webhook_url_env)
        end
      end
    end
  end
end

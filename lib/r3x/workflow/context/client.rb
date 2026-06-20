# frozen_string_literal: true

module R3x
  module Workflow
    class Context
      module Client
        extend self

        def http(verify_ssl: true, timeout: 10)
          R3x::Client::Http.new(verify_ssl:, timeout:)
        end

        def persistent_http(verify_ssl: true, timeout: 10, &)
          R3x::Client::Http.with_persistence(verify_ssl:, timeout:, &)
        end

        def prometheus(url_env: R3x::Client::Prometheus::DEFAULT_URL_ENV)
          R3x::Client::Prometheus.new(url_env:)
        end

        def healthchecks_io(check_uuid, ping_endpoint: nil, ping_endpoint_env: "HEALTHCHECKS_IO_URL")
          R3x::Client::HealthchecksIO.new(check_uuid, ping_endpoint:, ping_endpoint_env:)
        end

        def apify(api_key_env: R3x::Client::Apify::DEFAULT_API_KEY_ENV)
          R3x::Client::Apify.new(api_key: R3x::Env.secure_fetch(api_key_env, prefix: "#{R3x::Client::Apify::DEFAULT_API_KEY_ENV}_"))
        end

        def llm(api_key_env:, **)
          configuration = R3x::Client::Llm::ProviderConfiguration.resolve(api_key_env:)

          R3x::Client::Llm.new(
            api_key: configuration.api_key,
            config_api_key_attr: configuration.config_api_key_attr,
            **,
          )
        end

        def google_sheets(spreadsheet_id:, project:)
          R3x::Client::GoogleSheets.new(spreadsheet_id:, project:)
        end

        def gmail(project:)
          R3x::Client::Google::Gmail.new(project:)
        end

        def ocr(api_key_env: R3x::Client::Ocr::DEFAULT_API_KEY_ENV)
          R3x::Client::Ocr.new(api_key_env:)
        end

        def rss(url, timeout: 10)
          R3x::GemLoader.require("rss")
          ::RSS::Parser.parse(http(timeout:).get(url).body.to_s, false)
        end

        def google_translate(project:)
          R3x::Client::Google::Translate.new(project:)
        end

        def miniflux(
          url_env: R3x::Client::Miniflux::DEFAULT_URL_ENV,
          api_key_env: R3x::Client::Miniflux::DEFAULT_API_KEY_ENV
        )
          R3x::Client::Miniflux.new(url_env:, api_key_env:)
        end

        def wordpress(url:)
          R3x::Client::WordPress.new(url:)
        end

        def discord(webhook_url_env: R3x::Client::Discord::DEFAULT_WEBHOOK_URL_ENV)
          R3x::Client::Discord.new(webhook_url_env:)
        end

        def markdownify(url:, method: "auto", retain_images: false)
          R3x::Client::Markdownify.new(url:, method:, retain_images:).convert["markdown"]
        end
      end
    end
  end
end

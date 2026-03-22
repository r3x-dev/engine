# frozen_string_literal: true

module R3x
  module Workflow
    class Context
      include R3x::Concerns::Logger

      attr_reader :trigger, :execution, :workflow_class

      def initialize(trigger:, workflow_key:, workflow_class: nil)
        @trigger = trigger
        @workflow_class = workflow_class
        @execution = Execution.new(workflow_key: workflow_key)
      end

      def client
        @client ||= ClientProxy.new(workflow_class: workflow_class)
      end

      class ClientProxy
        def initialize(workflow_class:)
          @workflow_class = workflow_class
        end

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
            config_attr: "#{api_key_env.split("_").first.downcase}_api_key"
          )
        end

        def google_sheets(spreadsheet_id:, credentials_env:)
          R3x::Client::GoogleSheets.new(
            spreadsheet_id: spreadsheet_id,
            credentials: MultiJson.load(R3x::Env.secure_fetch(credentials_env, prefix: "GOOGLE_CREDENTIALS_"))
          )
        end

        private

        attr_reader :workflow_class
      end
    end
  end
end

# frozen_string_literal: true

module R3x
  module Outputs
    class Gmail
      include R3x::Concerns::Logger

      def initialize(credentials_env:, dry_run: nil)
        @credentials_env = credentials_env
        @dry_run = R3x::Policy.dry_run_for(:gmail, dry_run)
      end

      def deliver(to:, subject:, body:)
        if dry_run
          deliver_dry_run(to: to, subject: subject, body: body)
        else
          R3x::Client::Google::Gmail.new(credentials_env: credentials_env).deliver(
            to: to,
            subject: subject,
            body: body
          )
        end
      end

      private

      attr_reader :credentials_env, :dry_run

      def deliver_dry_run(to:, subject:, body:)
        logger.info("Gmail [DRY-RUN] to=#{to} subject=#{subject}\n#{body}")
        { "mode" => "dry-run" }
      end
    end
  end
end

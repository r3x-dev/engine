# frozen_string_literal: true

module R3x
  class Policy
    class << self
      def dry_run_for(key = nil, dry_run = nil)
        return true if R3x::Env.fetch_boolean("R3X_DRY_RUN")

        dry_run.nil? ? default_dry_run_for(key) : dry_run
      end

      def skip_cache?
        R3x::Env.fetch_boolean("R3X_SKIP_CACHE") || false
      end

      def validate_skip_cache!
        if Rails.env.production? && skip_cache?
          raise ArgumentError, "R3X_SKIP_CACHE must not be enabled at production boot; " \
            "use bin/workflow run --skip-cache for an explicit one-run override"
        end

        nil
      end

      def real_delivery_for?(key = nil, dry_run = nil)
        !dry_run_for(key, dry_run)
      end

      def default_dry_run_for(key = nil)
        override = env_override(key)
        return override unless override.nil?

        Rails.env.test? || Rails.env.development?
      end

      private

      def env_override(key)
        global = R3x::Env.fetch_boolean("R3X_DRY_RUN")
        return true if global

        value = R3x::Env.fetch_boolean(specific_dry_run_env_key(key)) if key.present?
        value.nil? ? global : value
      end

      def specific_dry_run_env_key(key)
        "R3X_#{key.to_s.upcase}_DRY_RUN"
      end
    end
  end
end

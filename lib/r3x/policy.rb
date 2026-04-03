# frozen_string_literal: true

module R3x
  class Policy
    class << self
      def dry_run_for(key = nil, dry_run = nil)
        dry_run.nil? ? default_dry_run_for(key) : dry_run
      end

      def skip_cache?
        R3x::Env.fetch_boolean("R3X_SKIP_CACHE") || false
      end

      def real_delivery_for?(key = nil, dry_run = nil)
        !dry_run_for(key, dry_run)
      end

      def default_dry_run_for(key = nil)
        override = env_override(key)
        return override unless override.nil?

        Rails.env.test?
      end

      private

      def env_override(key)
        return if key.blank?

        [ specific_dry_run_env_key(key), "R3X_DRY_RUN" ].each do |env_key|
          value = R3x::Env.fetch_boolean(env_key)
          next if value.nil?

          return value
        end

        nil
      end

      def specific_dry_run_env_key(key)
        "R3X_#{key.to_s.upcase}_DRY_RUN"
      end
    end
  end
end

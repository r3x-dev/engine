# frozen_string_literal: true

module R3x
  module Validators
    class CacheTtl
      class << self
        def validate!(ttl, field_name: "ttl")
          unless ttl.is_a?(Numeric) && ttl.to_i.positive?
            raise ArgumentError, "#{field_name} must be a positive duration"
          end

          max_age = solid_cache_max_age
          if max_age && ttl.to_i > max_age
            raise ArgumentError, "ttl can't exceed Solid Cache max_age configured in config/cache.yml"
          end

          ttl
        end

        private

        def solid_cache_max_age
          cache_store = Array(Rails.application.config.cache_store).first
          return unless cache_store == :solid_cache_store

          cache_config = Rails.application.config_for(:cache)
          max_age = cache_config.dig(:store_options, :max_age) || cache_config.dig("store_options", "max_age")

          max_age.to_i if max_age.present?
        end
      end
    end
  end
end

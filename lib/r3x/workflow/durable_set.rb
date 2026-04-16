# frozen_string_literal: true

require "digest"

module R3x
  module Workflow
    class DurableSet
      DEFAULT_TTL = 90.days

      def initialize(workflow_key:, name: :default, ttl: DEFAULT_TTL)
        @workflow_key = normalize!(workflow_key, label: "workflow_key")
        @name = normalize!(name, label: "name")
        @ttl = ttl

        validate_ttl!(ttl)
      end

      def include?(member)
        Rails.cache.exist?(cache_key_for(member))
      end

      def add(member, ttl: default_ttl)
        write(member, ttl: ttl)
      end

      def add?(member, ttl: default_ttl)
        write(member, ttl: ttl, unless_exist: true)
      end

      def delete(member)
        Rails.cache.delete(cache_key_for(member))
      end

      private

      attr_reader :workflow_key, :name, :ttl

      def default_ttl
        ttl
      end

      def write(member, ttl:, unless_exist: false)
        validate_ttl!(ttl)

        Rails.cache.write(
          cache_key_for(member),
          { "added_at" => Time.current.iso8601 },
          expires_in: ttl,
          unless_exist: unless_exist
        )
      end

      def validate_ttl!(ttl)
        max_age = solid_cache_max_age
        return ttl unless max_age && ttl.to_i > max_age

        raise ArgumentError, "ttl can't exceed Solid Cache max_age configured in config/cache.yml"
      end

      def solid_cache_max_age
        cache_store = Array(Rails.application.config.cache_store).first
        return unless cache_store == :solid_cache_store

        cache_config = Rails.application.config_for(:cache).to_h
        store_options = cache_config[:store_options] || cache_config["store_options"] || {}
        max_age = store_options[:max_age] || store_options["max_age"]

        max_age.to_i if max_age.present?
      end

      def cache_key_for(member)
        normalized_member = normalize!(member, label: "member")
        digest = Digest::SHA256.hexdigest(normalized_member)

        [ "r3x", "workflow", workflow_key, "durable_set", name, digest ].join(":")
      end

      def normalize!(value, label:)
        normalized = value.to_s.strip
        return normalized if normalized.present?

        raise ArgumentError, "#{label} can't be blank"
      end
    end
  end
end

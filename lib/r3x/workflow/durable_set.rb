# frozen_string_literal: true

require "digest"

module R3x
  module Workflow
    class DurableSet
      DEFAULT_TTL = 60.days

      def initialize(workflow_key:, name: :default, ttl: DEFAULT_TTL)
        @workflow_key = normalize!(workflow_key, label: "workflow_key")
        @name = normalize!(name, label: "name")
        @ttl = ttl
      end

      def include?(member)
        Rails.cache.exist?(cache_key_for(member))
      end

      def add(member, ttl: default_ttl)
        Rails.cache.write(
          cache_key_for(member),
          { "added_at" => Time.current.iso8601 },
          expires_in: ttl
        )
      end

      def add?(member, ttl: default_ttl)
        key = cache_key_for(member)
        return false if Rails.cache.exist?(key)

        Rails.cache.write(key, { "added_at" => Time.current.iso8601 }, expires_in: ttl)
        true
      end

      def delete(member)
        Rails.cache.delete(cache_key_for(member))
      end

      private

      attr_reader :workflow_key, :name, :ttl

      def default_ttl
        ttl
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

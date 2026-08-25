# frozen_string_literal: true

module R3x
  module Workflow
    class Base < ApplicationJob
      include ActiveJob::Continuable
      include Dsl

      CACHE_TTL = 1.day

      class << self
        def method_added(method_name)
          if method_name == :perform && self != Base
            raise ArgumentError, "Do not override #perform in #{name}. Override #run instead."
          end
          super
        end
      end

      def perform(trigger_key = nil, trigger_payload: nil)
        with_log_tags(*workflow_log_tags(trigger_key)) do
          @ctx = R3x::Workflow::Executor.build_context(
            workflow_class: self.class,
            trigger_key:,
            trigger_payload:,
            active_job_id: job_id,
          )
          if initial_execution?
            logger.info "Running workflow trigger_type=#{ctx.trigger.type}"
          else
            logger.info "Resuming workflow trigger_type=#{ctx.trigger.type} #{continuation.description}"
          end

          skip_reason = unmet_workflow_condition_reason
          if skip_reason
            result = { "status" => "skipped", "reason" => skip_reason }
            with_log_tags(R3x::Log.tag(R3x::Log::JOB_OUTCOME_TAG, "success")) { logger.info "Workflow run skipped reason=#{skip_reason}" }
            return result
          end

          result = run
          run_completion_callbacks
          with_log_tags(R3x::Log.tag(R3x::Log::JOB_OUTCOME_TAG, "success")) { logger.info "Workflow run completed" }
          result
        rescue => e
          with_log_tags(R3x::Log.tag(R3x::Log::JOB_OUTCOME_TAG, "failed")) { structured_error(message: "Workflow run failed", error: e) }
          raise
        ensure
          @ctx = nil
        end
      end

      def with_cache(force: false, key: nil, ttl: nil, &block)
        if R3x::Policy.skip_cache?
          logger.info "Skipping cache for #{self.class.name} due to policy"

          return yield
        end

        # TTL keys survive workflow edits until the bucket changes; plain keys below rotate with the file digest.
        unless ttl.nil?
          R3x::Validators::CacheTtl.validate!(ttl, field_name: "with_cache ttl")
          key = key.to_s.strip
          if key.blank?
            raise ArgumentError, "with_cache ttl requires a non-blank key"
          end

          cache_key = [
            "r3x",
            "workflow",
            self.class.workflow_key,
            "ttl",
            key,
            ttl.to_i,
            Time.current.to_i / ttl.to_i,
          ]

          return Rails.cache.fetch(cache_key, force:, expires_in: ttl, &block)
        end

        if Rails.env.production?
          raise "Plain with_cache is development-only and disabled in production; " \
            "use with_cache(key: <name>, ttl: <duration>) for periodic reuse that works in all environments"
        end

        cache_key = R3x::Workflow::CacheKey.generate(
          workflow_key: self.class.workflow_key,
          block:,
          method_name: __method__,
          key:,
        )

        Rails.cache.fetch(cache_key, force:, expires_in: CACHE_TTL, race_condition_ttl: 5.minutes, &block)
      end

      def run
        raise NotImplementedError, "#{self.class.name} must implement #run"
      end

      private

      attr_reader :ctx

      def workflow_dedup_key(value = nil, candidates: nil)
        R3x::Workflow::DedupKey.build(workflow_key: self.class.workflow_key, value:, candidates:)
      end

      def workflow_log_tags(trigger_key)
        [
          R3x::Log.tag(R3x::Log::TRIGGER_KEY_TAG, trigger_key),
        ]
      end

      def unmet_workflow_condition_reason
        return unless initial_execution?

        self.class._conditions.find { |condition| !send(condition.predicate) }&.reason
      end

      def run_completion_callbacks
        self.class._completion_callbacks.each { |callback| instance_exec(&callback) }
      end

      def initial_execution?
        !continuation.started?
      end
    end
  end
end

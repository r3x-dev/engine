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
            trigger_key: trigger_key,
            trigger_payload: trigger_payload
          )
          logger.info "Running workflow trigger_type=#{ctx.trigger.type}"

          result = run
          with_log_tags(R3x::Log.tag(R3x::Log::JOB_OUTCOME_TAG, "success")) do
            logger.info "Workflow run completed"
          end
          result
        rescue => e
          with_log_tags(R3x::Log.tag(R3x::Log::JOB_OUTCOME_TAG, "failed")) do
            structured_error(message: "Workflow run failed", error: e)
          end
          raise
        ensure
          @ctx = nil
        end
      end

      def with_cache(force: false, &block)
        if R3x::Policy.skip_cache?
          logger.info "Skipping cache for #{self.class.name} due to policy"

          return yield
        end

        if Rails.env.production?
          raise "with_cache is disabled in production, if you need to use it, please set R3X_SKIP_CACHE=true in the environment variables"
        end

        cache_key = R3x::Workflow::CacheKey.generate(
          workflow_key: self.class.workflow_key,
          block: block,
          method_name: __method__
        )

        Rails.cache.fetch(cache_key, force: force, expires_in: CACHE_TTL, race_condition_ttl: 5.minutes) do
          yield
        end
      end

      def run
        raise NotImplementedError, "#{self.class.name} must implement #run"
      end

      private

      attr_reader :ctx

      def workflow_dedup_key(value = nil, candidates: nil)
        R3x::Workflow::DedupKey.build(
          workflow_key: self.class.workflow_key,
          value: value,
          candidates: candidates
        )
      end

      def workflow_log_tags(trigger_key)
        [
          R3x::Log.tag(R3x::Log::TRIGGER_KEY_TAG, trigger_key)
        ]
      end
    end
  end
end

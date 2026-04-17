require "digest"

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
          begin
            context = R3x::Workflow::Executor.build_context(
              workflow_class: self.class,
              trigger_key: trigger_key,
              trigger_payload: trigger_payload
            )
            @ctx = context

            logger.info "Running workflow trigger_type=#{context.trigger.type}"

            run.tap do
              with_log_tags("r3x.job_outcome=success") do
                logger.info "Workflow run completed"
              end
            end
          rescue => e
            with_log_tags("r3x.job_outcome=failed") do
              logger.error "Workflow run failed error_class=#{e.class} error_message=#{e.message}"
            end

            raise
          ensure
            @ctx = nil
          end
        end
      end

      def with_cache(force: false, &block)
        if R3x::Policy.skip_cache?
          logger.info "Skipping cache for #{self.class.name} due to policy"

          return yield
        end

        if Rails.env.production?
          raise RuntimeError, "with_cache is disabled in production, if you need to use it, please set R3X_SKIP_CACHE=true in the environment variables"
        end

        Rails.cache.fetch(cache_key_for(block), force: force, expires_in: CACHE_TTL, race_condition_ttl: 5.minutes) do
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
          ("r3x.trigger_key=#{trigger_key}" if trigger_key.present?)
        ]
      end

      def cache_key_for(block)
        source = cache_block_source(block)
        digest = Digest::SHA256.hexdigest(source)

        [ "r3x", "workflow", self.class.workflow_key, digest ].join(":")
      end

      def cache_block_source(block)
        file, line = block.source_location
        return "#{file}:#{line}" unless file && File.exist?(file)

        extract_block_source(File.readlines(file), line)
      end

      def extract_block_source(lines, start_line)
        start_index = start_line - 1
        source_lines = []
        depth = 0
        started = false

        lines[start_index..].each do |line|
          source_lines << line

          if source_lines.length == 1
            source_lines[0] = source_lines[0].sub(/\A.*?(?=\bwith_cache\b)/, "")
          end

          depth += line.scan(/\bdo\b/).size
          depth += line.count("{")
          depth -= line.scan(/\bend\b/).size
          depth -= line.count("}")
          started ||= line.match?(/\bdo\b/) || line.include?("{")

          break if started && depth <= 0
        end

        source_lines.join.strip
      end
    end
  end
end

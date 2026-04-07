require "digest"

module R3x
  module Workflow
    class Base < ApplicationJob
      include ActiveJob::Continuable
      include Dsl
      include R3x::Concerns::Logger

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
        context = R3x::Workflow::Executor.build_context(
          workflow_class: self.class,
          trigger_key: trigger_key,
          trigger_payload: trigger_payload
        )
        @ctx = context

        run
      ensure
        @ctx = nil
      end

      def with_cache(force: false, &block)
        if R3x::Policy.skip_cache?
          logger.info "Skipping cache for #{self.class.name} due to policy"

          return yield
        end

        if Rails.env.production?
          raise RuntimeError, "with_cache is disabled in production"
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

# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module R3x
  class WorkflowCacheTest < ActiveSupport::TestCase
    test "with_cache reuses the cached result for identical block code" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::CacheTest"
        end

        def run
          @calls ||= 0

          with_cache do
            @calls += 1
            { "calls" => @calls }
          end
        end

        attr_reader :calls
      end

      workflow = workflow_class.new
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        first = workflow.run
        second = workflow.run

        assert_equal 1, workflow.calls
        assert_equal({ "calls" => 1 }, first)
        assert_equal({ "calls" => 1 }, second)
      ensure
        Rails.cache = original_cache
      end
    end

    test "with_cache refreshes when workflow file changes at the same call site" do
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      Dir.mktmpdir do |dir|
        path = File.join(dir, "workflow.rb")

        write_fragile_cache_workflow(path, "first")

        assert_equal "first", load_fragile_cache_workflow(path).new.run

        write_fragile_cache_workflow(path, "second")

        assert_equal "second", load_fragile_cache_workflow(path).new.run
      end
    ensure
      remove_fragile_cache_workflow
      Rails.cache = original_cache
    end

    test "with_cache raises when block source file cannot be fingerprinted" do
      block = proc { "cached" }
      block.stubs(:source_location).returns([nil, nil])

      error = assert_raises(RuntimeError) do
        R3x::Workflow::CacheKey.generate(workflow_key: "missing_cache_source_test", block:, method_name: :with_cache, key: "missing")
      end

      assert_equal "with_cache requires a block backed by a readable Ruby source file", error.message
    end

    test "with_cache raises when multiple cache calls share the same source line without keys" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::AmbiguousCacheLineTest"
        end
      end
      workflow = workflow_class.new

      error = assert_raises(RuntimeError) do
        [workflow.with_cache { "one" }, workflow.with_cache { "two" }]
      end

      assert_match(
        /with_cache cannot infer a unique cache key when multiple with_cache calls share line \d+; move them to separate lines or pass key:/,
        error.message,
      )
    end

    test "with_cache separates multiple calls on the same source line with explicit keys" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::SameLineCacheTest"
        end
      end
      workflow = workflow_class.new

      assert_equal(
        %w[one two],
        [
          workflow.with_cache(key: "one") { "one" },
          workflow.with_cache(key: "two") { "two" },
        ],
      )
    end

    test "with_cache allows method name text in strings and comments" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::CacheMethodTextTest"
        end

        def run
          with_cache { "with_cache" } # with_cache in a comment
        end
      end

      assert_equal "with_cache", workflow_class.new.run
    end

    test "with_cache force option bypasses the cached value" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ForceCacheTest"
        end

        def cached(force: false)
          @calls ||= 0

          with_cache(force:) do
            @calls += 1
            { "calls" => @calls }
          end
        end

        attr_reader :calls
      end

      workflow = workflow_class.new
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        workflow.cached
        workflow.cached(force: true)

        assert_equal 2, workflow.calls
      ensure
        Rails.cache = original_cache
      end
    end

    test "with_cache raises in production" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ProductionCacheGuard"
        end
      end

      workflow = workflow_class.new
      Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

      error = assert_raises(RuntimeError) do
        workflow.with_cache { "cached" }
      end

      assert_equal "with_cache is disabled in production, if you need to use it, please set R3X_SKIP_CACHE=true in the environment variables", error.message
    end

    test "with_cache bypasses cache when skip-cache override is enabled" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::SkipCacheTest"
        end

        def cached
          @calls ||= 0

          with_cache do
            @calls += 1
            { "calls" => @calls }
          end
        end
      end

      workflow = workflow_class.new
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache
      original_skip_cache = ENV["R3X_SKIP_CACHE"]

      Rails.cache = cache
      ENV["R3X_SKIP_CACHE"] = "true"

      begin
        first = workflow.cached
        second = workflow.cached

        assert_equal({ "calls" => 1 }, first)
        assert_equal({ "calls" => 2 }, second)
      ensure
        ENV["R3X_SKIP_CACHE"] = original_skip_cache
        Rails.cache = original_cache
      end
    end

    test "with_cache bypasses production guard when skip-cache override is enabled" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ProductionSkipCacheGuard"
        end
      end

      workflow = workflow_class.new
      original_skip_cache = ENV["R3X_SKIP_CACHE"]
      calls = 0

      Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))
      ENV["R3X_SKIP_CACHE"] = "true"

      result = workflow.with_cache do
        calls += 1
        { "calls" => calls }
      end

      assert_equal 1, calls
      assert_equal({ "calls" => 1 }, result)
    ensure
      ENV["R3X_SKIP_CACHE"] = original_skip_cache
    end

    private

    def write_fragile_cache_workflow(path, value)
      File.write(path, <<~RUBY)
        module Workflows
          class FragileCacheWorkflow < R3x::Workflow::Base
            def self.name
              "Workflows::FragileCacheWorkflow"
            end

            def run
              with_cache do
                ignored = "not a real end"
                # also not a real end
                text = <<~TEXT
                  still not a real end
                TEXT

                #{value.inspect}
              end
            end
          end
        end
      RUBY
    end

    def load_fragile_cache_workflow(path)
      remove_fragile_cache_workflow
      load path
      Workflows::FragileCacheWorkflow
    end

    def remove_fragile_cache_workflow
      Workflows.send(:remove_const, :FragileCacheWorkflow) if defined?(Workflows::FragileCacheWorkflow)
    end
  end
end

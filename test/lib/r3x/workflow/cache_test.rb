# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module R3x
  class WorkflowCacheTest < ActiveSupport::TestCase
    include ActiveSupport::Testing::TimeHelpers

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
      R3x::Workflow::CacheKey.stubs(:generate).raises("cache key generation should not run")

      error = assert_raises(RuntimeError) do
        workflow.with_cache { "cached" }
      end

      assert_equal "Plain with_cache is development-only and disabled in production; use with_cache(key: <name>, ttl: <duration>) for periodic reuse that works in all environments", error.message
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

    test "with_cache honors a late skip-cache override in production" do
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

    test "with_cache ttl reuses the cached result within the same period" do
      workflow = ttl_counter_workflow
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        travel_to Time.utc(2026, 8, 25, 10, 0) do
          first = workflow.cached
          second = workflow.cached

          assert_equal({ "calls" => 1 }, first)
          assert_equal({ "calls" => 1 }, second)
        end

        assert_equal 1, workflow.calls
      ensure
        Rails.cache = original_cache
      end
    end

    test "with_cache ttl keeps its key across workflow file edits" do
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      travel_to Time.utc(2026, 8, 25, 10, 0) do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "workflow.rb")

          write_stable_ttl_cache_workflow(path, "first")

          assert_equal "first", load_stable_ttl_cache_workflow(path).new.run

          write_stable_ttl_cache_workflow(path, "second")

          assert_equal "first", load_stable_ttl_cache_workflow(path).new.run
        end
      end
    ensure
      remove_stable_ttl_cache_workflow
      Rails.cache = original_cache
    end

    test "with_cache ttl recomputes after the period elapses" do
      workflow = ttl_counter_workflow
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        travel_to Time.utc(2026, 8, 25, 10, 0) do
          workflow.cached
        end

        travel_to Time.utc(2026, 8, 26, 12, 0) do
          workflow.cached
        end

        assert_equal 2, workflow.calls
      ensure
        Rails.cache = original_cache
      end
    end

    test "with_cache ttl works in production" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ProductionTtlCache"
        end

        def cached
          @calls ||= 0

          with_cache(key: "expensive_fetch", ttl: 24.hours) do
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
      Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))
      begin
        first = workflow.cached
        second = workflow.cached

        assert_equal({ "calls" => 1 }, first)
        assert_equal({ "calls" => 1 }, second)
      ensure
        Rails.cache = original_cache
      end
    end

    test "with_cache ttl force refreshes the cached value" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ForceTtlCacheTest"
        end

        def cached(force: false)
          @calls ||= 0

          with_cache(force:, key: "expensive_fetch", ttl: 24.hours) do
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
        travel_to Time.utc(2026, 8, 25, 10, 0) do
          workflow.cached
          workflow.cached(force: true)
        end

        assert_equal 2, workflow.calls
      ensure
        Rails.cache = original_cache
      end
    end

    test "with_cache ttl bypasses cache when skip-cache override is enabled" do
      workflow = ttl_counter_workflow
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache
      original_skip_cache = ENV["R3X_SKIP_CACHE"]

      Rails.cache = cache
      ENV["R3X_SKIP_CACHE"] = "true"

      begin
        travel_to Time.utc(2026, 8, 25, 10, 0) do
          first = workflow.cached
          second = workflow.cached

          assert_equal({ "calls" => 1 }, first)
          assert_equal({ "calls" => 2 }, second)
        end
      ensure
        ENV["R3X_SKIP_CACHE"] = original_skip_cache
        Rails.cache = original_cache
      end
    end

    test "with_cache rejects invalid ttl values" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::InvalidTtlTest"
        end
      end
      workflow = workflow_class.new

      assert_raises(ArgumentError) { workflow.with_cache(key: "expensive_fetch", ttl: 0.hours) { "cached" } }
      assert_raises(ArgumentError) { workflow.with_cache(key: "expensive_fetch", ttl: -1.hour) { "cached" } }
      assert_raises(ArgumentError) { workflow.with_cache(key: "expensive_fetch", ttl: false) { "cached" } }
      assert_raises(ArgumentError) { workflow.with_cache(key: "expensive_fetch", ttl: "3600") { "cached" } }
    end

    test "with_cache ttl requires a stable key" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::MissingTtlKeyTest"
        end
      end

      error = assert_raises(ArgumentError) do
        workflow_class.new.with_cache(ttl: 1.hour) { "cached" }
      end

      assert_equal "with_cache ttl requires a non-blank key", error.message
    end

    test "with_cache rejects ttl above configured Solid Cache max_age" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ExcessiveTtlTest"
        end
      end
      workflow = workflow_class.new

      Rails.application.config.stubs(:cache_store).returns(:solid_cache_store)
      Rails.application.stubs(:config_for).with(:cache).returns({ store_options: { max_age: 90.days.to_i } })

      error = assert_raises(ArgumentError) do
        workflow.with_cache(key: "expensive_fetch", ttl: 91.days) { "cached" }
      end

      assert_equal "ttl can't exceed Solid Cache max_age configured in config/cache.yml", error.message
    end

    private

    def ttl_counter_workflow
      Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::TtlCacheTest"
        end

        def cached
          @calls ||= 0

          with_cache(key: "expensive_fetch", ttl: 24.hours) do
            @calls += 1
            { "calls" => @calls }
          end
        end

        attr_reader :calls
      end.new
    end

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

    def write_stable_ttl_cache_workflow(path, value)
      File.write(path, <<~RUBY)
        module Workflows
          class StableTtlCacheWorkflow < R3x::Workflow::Base
            def run
              with_cache(key: "source", ttl: 1.hour) do
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

    def load_stable_ttl_cache_workflow(path)
      remove_stable_ttl_cache_workflow
      load path
      Workflows::StableTtlCacheWorkflow
    end

    def remove_fragile_cache_workflow
      Workflows.send(:remove_const, :FragileCacheWorkflow) if defined?(Workflows::FragileCacheWorkflow)
    end

    def remove_stable_ttl_cache_workflow
      Workflows.send(:remove_const, :StableTtlCacheWorkflow) if defined?(Workflows::StableTtlCacheWorkflow)
    end
  end
end

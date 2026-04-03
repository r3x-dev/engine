require "test_helper"
require_relative "../../support/fake_change_detecting_trigger"

module R3x
  class WorkflowTest < ActiveSupport::TestCase
    test "workflow_key is derived from class name by convention" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::MyAwesomeWorkflow"
        end
      end

      assert_equal "my_awesome_workflow", klass.workflow_key
    end

    test "workflow_key works for single word class" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::Test"
        end
      end

      assert_equal "test", klass.workflow_key
    end

    test "trigger :schedule requires cron option" do
      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end
          trigger :schedule
        end
      end

      assert_includes error.message, "Invalid trigger :schedule for Test"
      assert_includes error.message, "Cron can't be blank"
    end

    test "trigger :schedule accepts valid cron expression" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Test"
        end
        trigger :schedule, cron: "0 13 * * *"
      end

      schedule = klass.schedulable_triggers.first
      assert schedule
      assert_equal :schedule, schedule.type
      assert_equal "0 13 * * *", schedule.cron
    end

    test "trigger :schedule accepts human readable cron" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Test"
        end
        trigger :schedule, cron: "every day at 13:00"
      end

      schedule = klass.schedulable_triggers.first
      assert schedule
      assert_equal "every day at 13:00", schedule.cron
    end

    test "trigger :schedule rejects invalid cron" do
      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end
          trigger :schedule, cron: "invalid cron syntax"
        end
      end

      assert_includes error.message, "Cron is not a valid cron expression"
    end

    test "unknown trigger type raises error" do
      assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end
          trigger :unknown
        end
      end
    end

    test "triggers returns all registered triggers" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Test"
        end
        trigger :schedule, cron: "0 * * * *"
      end

      triggers = klass.triggers
      assert_equal 1, triggers.size
      assert_equal [ :schedule ], triggers.map(&:type)
    end

    test "trigger :schedule rejects blank cron (empty string and whitespace)" do
      [
        "",
        "   "
      ].each do |cron|
        error = assert_raises(ConfigurationError) do
          Class.new(R3x::Workflow::Base) do
            def self.name
              "Test"
            end
            trigger :schedule, cron: cron
          end
        end

        assert_includes error.message, "Cron can't be blank"
      end
    end

    test "supported_types returns list of available trigger files" do
      types = R3x::Triggers.supported_types
      assert_includes types, :schedule
      refute_includes types, :base
    end

    test "unknown trigger type raises error with dynamic supported types list" do
      error = assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end
          trigger :nonexistent
        end
      end

      assert_match(/Unknown trigger type: nonexistent/, error.message)
      assert_match(/Supported types:.*:schedule/, error.message)
    end

    test "rejects duplicate change-detecting trigger keys in one workflow" do
      original_resolve = R3x::Triggers.method(:resolve)

      R3x::Triggers.define_singleton_method(:resolve) do |_type|
        R3x::TestSupport::FakeChangeDetectingTrigger
      end

      error = assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Workflows::DuplicateChangeDetecting"
          end

          trigger :fake_change_detecting, identity: "same"
          trigger :fake_change_detecting, identity: "same", cron: "every hour"
        end
      end

      assert_match(/Trigger with key .* already exists/, error.message)
    ensure
      R3x::Triggers.define_singleton_method(:resolve, original_resolve)
    end

    test "change-detecting trigger key does not change when only cron changes" do
      trigger_one = R3x::TestSupport::FakeChangeDetectingTrigger.new(identity: "feed", cron: "every 15 minutes")
      trigger_two = R3x::TestSupport::FakeChangeDetectingTrigger.new(identity: "feed", cron: "every hour")

      assert_equal trigger_one.unique_key, trigger_two.unique_key
    end

    # Default trigger behavior tests

    test "returns default Manual trigger when no triggers declared" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NoTriggers"
        end
      end

      triggers = klass.triggers
      assert_equal 1, triggers.size
      assert_equal :manual, triggers.first.type
    end

    test "returns declared triggers when triggers are declared" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::WithTriggers"
        end

        trigger :manual
      end

      triggers = klass.triggers
      assert_equal 1, triggers.size
      assert_equal :manual, triggers.first.type
    end

    test "perform does not fallback to manual trigger for unknown trigger key" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::StrictTriggerLookup"
        end

        trigger :manual

        def run
          raise "should not execute"
        end
      end

      error = assert_raises(ArgumentError) do
        workflow_class.perform_now("missing-trigger")
      end

      assert_match(/Unknown trigger key 'missing-trigger'/, error.message)
    end

    test "perform accepts auto-generated manual trigger when no triggers are declared" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ImplicitManual"
        end

        def run
          { "trigger_type" => ctx.trigger.type.to_s }
        end
      end

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal "manual", result["trigger_type"]
    end

    test "perform without trigger key uses manual trigger for schedule-only workflow" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ManualFallback"
        end

        trigger :schedule, cron: "0 * * * *"

        def run
          { "trigger_type" => ctx.trigger.type.to_s }
        end
      end

      result = workflow_class.perform_now

      assert_equal "manual", result["trigger_type"]
    end

    test "perform exposes ctx helper to workflows" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ContextHelper"
        end

        trigger :manual

        def run
          { "trigger_type" => ctx.trigger.type.to_s }
        end
      end

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal "manual", result["trigger_type"]
    end

    test "perform does not reload workflow packs" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NoPackReload"
        end

        trigger :manual

        def run
          { "trigger_type" => ctx.trigger.type.to_s }
        end
      end

      original_load = R3x::Workflow::PackLoader.method(:load!)
      R3x::Workflow::PackLoader.singleton_class.send(:define_method, :load!) do |*|
        raise "should not reload packs during workflow execution"
      end

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal "manual", result["trigger_type"]
    ensure
      R3x::Workflow::PackLoader.singleton_class.send(:define_method, :load!, original_load)
    end

    test "prevents overriding perform method in subclasses" do
      error = assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Workflows::BadWorkflow"
          end

          def perform
            # This should raise an error
          end
        end
      end

      assert_match(/Do not override #perform/, error.message)
      assert_match(/Override #run instead/, error.message)
    end

    test "schedulable_triggers excludes auto-generated Manual triggers" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NoExplicitTriggers"
        end
      end

      # Should return empty array, not the auto-generated Manual trigger
      assert_empty klass.schedulable_triggers
    end

    test "triggers_by_key excludes auto-generated Manual triggers" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NoExplicitTriggers"
        end
      end

      # Should return empty hash, not the auto-generated Manual trigger
      assert_empty klass.triggers_by_key
    end

    test "with_cache reuses the cached result for identical block code" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::CacheTest"
        end
      end

      workflow = workflow_class.new
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache
      calls = 0

      Rails.cache = cache
      begin
        first = workflow.with_cache { calls += 1; { "calls" => calls } }
        second = workflow.with_cache { calls += 1; { "calls" => calls } }

        assert_equal 1, calls
        assert_equal({ "calls" => 1 }, first)
        assert_equal({ "calls" => 1 }, second)
      ensure
        Rails.cache = original_cache
      end
    end

    test "with_cache regenerates the cache key when block code changes" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::CacheKeyTest"
        end
      end

      workflow = workflow_class.new

      key_one = workflow.send(:cache_key_for, proc { "one" })
      key_two = workflow.send(:cache_key_for, proc { "two" })

      refute_equal key_one, key_two
    end

    test "with_cache force option bypasses the cached value" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::ForceCacheTest"
        end
      end

      workflow = workflow_class.new
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache
      calls = 0

      Rails.cache = cache
      begin
        workflow.with_cache { calls += 1; { "calls" => calls } }
        workflow.with_cache(force: true) { calls += 1; { "calls" => calls } }

        assert_equal 2, calls
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
      original_env = Rails.method(:env)
      Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new("production") }

      error = assert_raises(RuntimeError) do
        workflow.with_cache { "cached" }
      end

      assert_equal "with_cache is disabled in production", error.message
    ensure
      Rails.define_singleton_method(:env, original_env)
    end

    test "with_cache bypasses cache when skip-cache override is enabled" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::SkipCacheTest"
        end
      end

      workflow = workflow_class.new
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache
      original_skip_cache = ENV["R3X_SKIP_CACHE"]
      calls = 0

      Rails.cache = cache
      ENV["R3X_SKIP_CACHE"] = "true"

      begin
        first = workflow.with_cache { calls += 1; { "calls" => calls } }
        second = workflow.with_cache { calls += 1; { "calls" => calls } }

        assert_equal 2, calls
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
      original_env = Rails.method(:env)
      original_skip_cache = ENV["R3X_SKIP_CACHE"]
      calls = 0

      Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new("production") }
      ENV["R3X_SKIP_CACHE"] = "true"

      result = workflow.with_cache do
        calls += 1
        { "calls" => calls }
      end

      assert_equal 1, calls
      assert_equal({ "calls" => 1 }, result)
    ensure
      ENV["R3X_SKIP_CACHE"] = original_skip_cache
      Rails.define_singleton_method(:env, original_env)
    end
  end
end

require "test_helper"
require_relative "../../support/fake_change_detecting_trigger"

module R3x
  class WorkflowTest < ActiveSupport::TestCase
    class DedupHelperWorkflow < R3x::Workflow::Base
      trigger :schedule, cron: "0 * * * *"

      def run
        workflow_dedup_key(candidates: [ nil, "post-123" ])
      end
    end

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

    test "base exposes workflow_dedup_key helper" do
      assert_equal "wf:dedup_helper_workflow:post-123", DedupHelperWorkflow.new.run
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
      original_timezone = ENV["R3X_TIMEZONE"]
      ENV.delete("R3X_TIMEZONE")

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
      assert_nil schedule.timezone
      assert_equal "0 13 * * *", schedule.schedule
    ensure
      ENV["R3X_TIMEZONE"] = original_timezone
    end

    test "trigger :schedule accepts human readable cron" do
      original_timezone = ENV["R3X_TIMEZONE"]
      ENV.delete("R3X_TIMEZONE")

      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Test"
        end
        trigger :schedule, cron: "every day at 13:00"
      end

      schedule = klass.schedulable_triggers.first
      assert schedule
      assert_equal "every day at 13:00", schedule.cron
      assert_nil schedule.timezone
      assert_equal "every day at 13:00", schedule.schedule
    ensure
      ENV["R3X_TIMEZONE"] = original_timezone
    end

    test "trigger :schedule accepts timezone" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Test"
        end

        trigger :schedule, cron: "0 13 * * *", timezone: "Europe/Paris"
      end

      schedule = klass.schedulable_triggers.first
      assert schedule
      assert_equal "Europe/Paris", schedule.timezone
      assert_equal "0 13 * * * Europe/Paris", schedule.schedule
    end

    test "trigger :schedule normalizes Rails timezone names to TZInfo names" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Test"
        end

        trigger :schedule, cron: "0 13 * * *", timezone: "Pacific Time (US & Canada)"
      end

      schedule = klass.schedulable_triggers.first
      assert schedule
      assert_equal "America/Los_Angeles", schedule.timezone
      assert_equal "0 13 * * * America/Los_Angeles", schedule.schedule
    end

    test "trigger :schedule uses default timezone from env" do
      original_timezone = ENV["R3X_TIMEZONE"]
      ENV["R3X_TIMEZONE"] = "UTC"

      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Test"
        end

        trigger :schedule, cron: "0 13 * * *"
      end

      schedule = klass.schedulable_triggers.first
      assert schedule
      assert_equal "UTC", schedule.timezone
      assert_equal "0 13 * * * UTC", schedule.schedule
    ensure
      ENV["R3X_TIMEZONE"] = original_timezone
    end

    test "trigger :schedule uses timezone embedded in cron" do
      original_timezone = ENV["R3X_TIMEZONE"]
      ENV["R3X_TIMEZONE"] = "UTC"

      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Test"
        end

        trigger :schedule, cron: "every day at 13:00 Europe/Paris"
      end

      schedule = klass.schedulable_triggers.first
      assert schedule
      assert_equal "Europe/Paris", schedule.timezone
      assert_equal "every day at 13:00 Europe/Paris", schedule.schedule
    ensure
      ENV["R3X_TIMEZONE"] = original_timezone
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

    test "trigger :schedule rejects invalid timezone" do
      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end

          trigger :schedule, cron: "0 13 * * *", timezone: "Mars/Olympus"
        end
      end

      assert_includes error.message, "Timezone timezone: 'Mars/Olympus' is not a valid timezone"
    end

    test "trigger :schedule rejects invalid default timezone from env" do
      original_timezone = ENV["R3X_TIMEZONE"]
      ENV["R3X_TIMEZONE"] = "Mars/Olympus"

      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end

          trigger :schedule, cron: "0 13 * * *"
        end
      end

      assert_includes error.message, "Timezone timezone: 'Mars/Olympus' is not a valid timezone"
    ensure
      ENV["R3X_TIMEZONE"] = original_timezone
    end

    test "trigger :schedule rejects conflicting timezone option and embedded cron timezone" do
      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end

          trigger :schedule, cron: "0 13 * * * Europe/Paris", timezone: "UTC"
        end
      end

      assert_includes error.message, "use either timezone: or a timezone embedded in cron, not both"
    end

    test "trigger :schedule rejects matching timezone option and embedded cron timezone" do
      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Test"
          end

          trigger :schedule, cron: "0 13 * * * Europe/Paris", timezone: "Europe/Paris"
        end
      end

      assert_includes error.message, "use either timezone: or a timezone embedded in cron, not both"
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

    test "uses declares workflow capabilities" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NetworkedWorkflow"
        end

        uses :networking
      end

      assert_equal Set.new([ :networking ]), klass.capabilities
      assert klass.uses?(:networking)
      refute klass.uses?(:filesystem)
    end

    test "uses raises on duplicate capability" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::DuplicateCap"
        end

        uses :networking
      end

      error = assert_raises(ArgumentError) do
        klass.uses(:networking)
      end

      assert_match "Capability already declared", error.message
    end

    test "uses raises on unknown capability" do
      error = assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Workflows::BadCap"
          end

          uses :hacking
        end
      end

      assert_match "Unknown capabilities: hacking", error.message
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
      R3x::Triggers.stubs(:resolve).returns(R3x::TestSupport::FakeChangeDetectingTrigger)

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

      R3x::Workflow::PackLoader.stubs(:load!).raises("should not reload packs during workflow execution")

      result = workflow_class.perform_now(workflow_class.triggers.first.unique_key)

      assert_equal "manual", result["trigger_type"]
    end

    test "perform logs workflow run outcome" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::LoggedWorkflow"
        end

        trigger :manual

        def run
          { "status" => "ok" }
        end
      end

      output = capture_logged_output do
        workflow_class.perform_now(workflow_class.triggers.first.unique_key)
      end

      assert_includes output, "Running workflow trigger_type=manual"
      assert_includes output, "r3x.run_active_job_id="
      assert_includes output, "r3x.trigger_key="
      refute_includes output, "r3x.workflow_key=logged_workflow"
      assert_includes output, "r3x.job_outcome=success"
      assert_includes output, "Workflow run completed"
    end

    test "perform logs workflow failure outcome" do
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::FailingWorkflow"
        end

        trigger :manual

        def run
          raise ArgumentError, "boom"
        end
      end

      output = capture_logged_output do
        assert_raises(ArgumentError) do
          workflow_class.perform_now(workflow_class.triggers.first.unique_key)
        end
      end

      assert_includes output, "r3x.job_outcome=failed"
      assert_includes output, "Workflow run failed"
      assert_includes output, "\"error_class\":\"ArgumentError\""
      assert_includes output, "\"error_message\":\"boom\""
      assert_includes output, "\"backtrace\":["
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

    test "ctx durable_set stores membership across calls" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "durable_set_workflow",
          payload: nil
        ),
        workflow_key: "durable_set_workflow"
      )
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        durable_set = context.durable_set

        refute durable_set.include?("item-1")
        durable_set.add("item-1")
        assert durable_set.include?("item-1")
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set scopes keys by set name" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "named_durable_set_workflow",
          payload: nil
        ),
        workflow_key: "named_durable_set_workflow"
      )
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        default_set = context.durable_set
        sent_set = context.durable_set(:sent)

        default_set.add("item-1")

        assert default_set.include?("item-1")
        refute sent_set.include?("item-1")
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set scopes keys by workflow" do
      trigger = R3x::Triggers::Manual.new
      first_context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(trigger: trigger, workflow_key: "workflow_one", payload: nil),
        workflow_key: "workflow_one"
      )
      second_context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(trigger: trigger, workflow_key: "workflow_two", payload: nil),
        workflow_key: "workflow_two"
      )
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        first_context.durable_set.add("item-1")

        assert first_context.durable_set.include?("item-1")
        refute second_context.durable_set.include?("item-1")
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set uses ninety day default ttl" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "default_ttl_workflow",
          payload: nil
        ),
        workflow_key: "default_ttl_workflow"
      )
      cache = Class.new do
        attr_reader :writes

        def initialize
          @writes = []
        end

        def write(key, value, expires_in:, unless_exist: false)
          writes << { key: key, value: value, expires_in: expires_in, unless_exist: unless_exist }
          true
        end
      end.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        context.durable_set.add("item-1")

        assert_equal 90.days, cache.writes.last[:expires_in]
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set rejects ttl above configured Solid Cache max_age" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "ttl_validation_workflow",
          payload: nil
        ),
        workflow_key: "ttl_validation_workflow"
      )
      Rails.application.config.stubs(:cache_store).returns(:solid_cache_store)
      Rails.application.stubs(:config_for).with(:cache).returns({ store_options: { max_age: 90.days.to_i } })

      error = assert_raises(ArgumentError) do
        context.durable_set(ttl: 91.days)
      end

      assert_equal "ttl can't exceed Solid Cache max_age configured in config/cache.yml", error.message
    end

    test "ctx durable_set rejects per-call ttl above configured Solid Cache max_age" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "per_call_ttl_validation_workflow",
          payload: nil
        ),
        workflow_key: "per_call_ttl_validation_workflow"
      )

      Rails.application.config.stubs(:cache_store).returns(:solid_cache_store)
      Rails.application.stubs(:config_for).with(:cache).returns({ store_options: { max_age: 90.days.to_i } })

      durable_set = context.durable_set

      error = assert_raises(ArgumentError) do
        durable_set.add("item-1", ttl: 91.days)
      end

      assert_equal "ttl can't exceed Solid Cache max_age configured in config/cache.yml", error.message
    end

    test "ctx durable_set add? returns true for new members and false for existing" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "add_predicate_workflow",
          payload: nil
        ),
        workflow_key: "add_predicate_workflow"
      )
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        durable_set = context.durable_set

        assert durable_set.add?("item-1")
        refute durable_set.add?("item-1")
        assert durable_set.include?("item-1")

        assert durable_set.add?("item-2")
        refute durable_set.add?("item-2")
        assert durable_set.include?("item-2")
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set add? uses atomic cache writes" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "atomic_add_predicate_workflow",
          payload: nil
        ),
        workflow_key: "atomic_add_predicate_workflow"
      )
      cache = Class.new do
        attr_reader :writes

        def initialize
          @writes = []
          @written = false
        end

        def exist?(_key)
          raise "add? must not check existence separately"
        end

        def write(key, value, expires_in:, unless_exist: false)
          writes << { key: key, value: value, expires_in: expires_in, unless_exist: unless_exist }
          return false if unless_exist && @written

          @written = true
        end
      end.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        durable_set = context.durable_set

        assert durable_set.add?("item-1")
        refute durable_set.add?("item-1")
        assert_equal [ true, true ], cache.writes.map { |write| write[:unless_exist] }
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set deletes members" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "delete_durable_set_workflow",
          payload: nil
        ),
        workflow_key: "delete_durable_set_workflow"
      )
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        durable_set = context.durable_set
        durable_set.add("item-1")

        assert durable_set.include?("item-1")

        durable_set.delete("item-1")

        refute durable_set.include?("item-1")
      ensure
        Rails.cache = original_cache
      end
    end
  end
end

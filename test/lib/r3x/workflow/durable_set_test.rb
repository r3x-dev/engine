# frozen_string_literal: true

require "test_helper"

module R3x
  class WorkflowDurableSetTest < ActiveSupport::TestCase
    test "ctx durable_set stores membership across calls" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "durable_set_workflow",
          payload: nil,
        ),
        workflow_key: "durable_set_workflow",
      )
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        durable_set = context.durable_set

        assert_not_includes durable_set, "item-1"
        durable_set.add("item-1")

        assert_includes durable_set, "item-1"
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set scopes keys by set name" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "named_durable_set_workflow",
          payload: nil,
        ),
        workflow_key: "named_durable_set_workflow",
      )
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        default_set = context.durable_set
        sent_set = context.durable_set(:sent)

        default_set.add("item-1")

        assert_includes default_set, "item-1"
        assert_not_includes sent_set, "item-1"
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set scopes keys by workflow" do
      trigger = R3x::Triggers::Manual.new
      first_context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(trigger:, workflow_key: "workflow_one", payload: nil),
        workflow_key: "workflow_one",
      )
      second_context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(trigger:, workflow_key: "workflow_two", payload: nil),
        workflow_key: "workflow_two",
      )
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        first_context.durable_set.add("item-1")

        assert_includes first_context.durable_set, "item-1"
        assert_not_includes second_context.durable_set, "item-1"
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set uses ninety day default ttl" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "default_ttl_workflow",
          payload: nil,
        ),
        workflow_key: "default_ttl_workflow",
      )
      cache = Class.new do
        attr_reader :writes

        def initialize
          @writes = []
        end

        def write(key, value, expires_in:, unless_exist: false)
          writes << { key:, value:, expires_in:, unless_exist: }
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
          payload: nil,
        ),
        workflow_key: "ttl_validation_workflow",
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
          payload: nil,
        ),
        workflow_key: "per_call_ttl_validation_workflow",
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
          payload: nil,
        ),
        workflow_key: "add_predicate_workflow",
      )
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        durable_set = context.durable_set

        assert durable_set.add?("item-1")
        assert_not durable_set.add?("item-1")
        assert_includes durable_set, "item-1"

        assert durable_set.add?("item-2")
        assert_not durable_set.add?("item-2")
        assert_includes durable_set, "item-2"
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set add? uses atomic cache writes" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "atomic_add_predicate_workflow",
          payload: nil,
        ),
        workflow_key: "atomic_add_predicate_workflow",
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
          writes << { key:, value:, expires_in:, unless_exist: }
          return false if unless_exist && @written

          @written = true
        end
      end.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        durable_set = context.durable_set

        assert durable_set.add?("item-1")
        assert_not durable_set.add?("item-1")
        assert_equal [true, true], cache.writes.map { |write| write[:unless_exist] }
      ensure
        Rails.cache = original_cache
      end
    end

    test "ctx durable_set deletes members" do
      context = R3x::Workflow::Context.new(
        trigger: R3x::TriggerManager::Execution.new(
          trigger: R3x::Triggers::Manual.new,
          workflow_key: "delete_durable_set_workflow",
          payload: nil,
        ),
        workflow_key: "delete_durable_set_workflow",
      )
      cache = ActiveSupport::Cache::MemoryStore.new
      original_cache = Rails.cache

      Rails.cache = cache
      begin
        durable_set = context.durable_set
        durable_set.add("item-1")

        assert_includes durable_set, "item-1"

        durable_set.delete("item-1")

        assert_not_includes durable_set, "item-1"
      ensure
        Rails.cache = original_cache
      end
    end
  end
end

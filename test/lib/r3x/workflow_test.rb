require "test_helper"
require_relative "../../support/fake_change_detecting_trigger"

module R3x
  class WorkflowTest < ActiveSupport::TestCase
    test "workflow_key is derived from class name by convention" do
      klass = Class.new(R3x::Workflow) do
        def self.name
          "Workflows::MyAwesomeWorkflow"
        end
      end

      assert_equal "my_awesome_workflow", klass.workflow_key
    end

    test "workflow_key works for single word class" do
      klass = Class.new(R3x::Workflow) do
        def self.name
          "Workflows::Test"
        end
      end

      assert_equal "test", klass.workflow_key
    end

    test "trigger :schedule requires cron option" do
      error = assert_raises(ConfigurationError) do
        Class.new(R3x::Workflow) do
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
      klass = Class.new(R3x::Workflow) do
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
      klass = Class.new(R3x::Workflow) do
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
        Class.new(R3x::Workflow) do
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
        Class.new(R3x::Workflow) do
          def self.name
            "Test"
          end
          trigger :unknown
        end
      end
    end

    test "triggers returns all registered triggers" do
      klass = Class.new(R3x::Workflow) do
        def self.name
          "Test"
        end
        trigger :schedule, cron: "0 13 * * *"
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
          Class.new(R3x::Workflow) do
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
        Class.new(R3x::Workflow) do
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

      error = begin
        assert_raises(ArgumentError) do
          Class.new(R3x::Workflow) do
            def self.name
              "Workflows::DuplicateChangeDetecting"
            end

            trigger :fake_change_detecting, identity: "same"
            trigger :fake_change_detecting, identity: "same", cron: "every hour"
          end
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
  end
end

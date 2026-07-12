# frozen_string_literal: true

require "test_helper"

module R3x
  class WorkflowDslTest < ActiveSupport::TestCase
    class DedupHelperWorkflow < R3x::Workflow::Base
      trigger :schedule, cron: "0 * * * *"

      def run
        workflow_dedup_key(candidates: [nil, "post-123"])
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
      assert_equal [:schedule], triggers.map(&:type)
    end

    test "trigger :schedule rejects blank cron (empty string and whitespace)" do
      [
        "",
        "   ",
      ].each do |cron|
        error = assert_raises(ConfigurationError) do
          Class.new(R3x::Workflow::Base) do
            def self.name
              "Test"
            end
            trigger(:schedule, cron:)
          end
        end

        assert_includes error.message, "Cron can't be blank"
      end
    end

    test "supported_types returns list of available trigger files" do
      types = R3x::Triggers.supported_types

      assert_includes types, :schedule
      assert_not_includes types, :base
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
  end
end

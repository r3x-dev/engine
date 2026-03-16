require "test_helper"
require "r3x/workflow"

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
      assert_raises(ArgumentError) do
        Class.new(R3x::Workflow) do
          def self.name
            "Test"
          end
          trigger :schedule
        end
      end
    end

    test "trigger :schedule accepts valid cron expression" do
      klass = Class.new(R3x::Workflow) do
        def self.name
          "Test"
        end
        trigger :schedule, cron: "0 13 * * *"
      end

      schedule = klass.triggers.find(&:cron_schedulable?)
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

      schedule = klass.triggers.find(&:cron_schedulable?)
      assert schedule
      assert_equal "every day at 13:00", schedule.cron
    end

    test "trigger :schedule rejects invalid cron" do
      assert_raises(ArgumentError) do
        Class.new(R3x::Workflow) do
          def self.name
            "Test"
          end
          trigger :schedule, cron: "invalid cron syntax"
        end
      end
    end

    test "trigger :rss requires url option" do
      assert_raises(ArgumentError) do
        Class.new(R3x::Workflow) do
          def self.name
            "Test"
          end
          trigger :rss
        end
      end
    end

    test "trigger :rss with url and default every" do
      klass = Class.new(R3x::Workflow) do
        def self.name
          "Test"
        end
        trigger :rss, url: "https://example.com/rss"
      end

      rss = klass.triggers.first
      assert rss
      assert_equal :rss, rss.type
      assert_equal "https://example.com/rss", rss.url
      assert_equal "every hour", rss.every
    end

    test "trigger :rss with custom every" do
      klass = Class.new(R3x::Workflow) do
        def self.name
          "Test"
        end
        trigger :rss, url: "https://example.com/rss", every: "every 15 minutes"
      end

      rss = klass.triggers.first
      assert rss
      assert_equal "every 15 minutes", rss.every
    end

    test "trigger :rss validates every is valid cron" do
      assert_raises(ArgumentError) do
        Class.new(R3x::Workflow) do
          def self.name
            "Test"
          end
          trigger :rss, url: "https://example.com/rss", every: "not valid"
        end
      end
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
        trigger :rss, url: "https://example.com/rss"
      end

      triggers = klass.triggers
      assert_equal 2, triggers.size
      assert_equal [ :schedule, :rss ], triggers.map(&:type)
    end

    test "trigger :schedule rejects blank cron" do
      assert_raises(ArgumentError) do
        Class.new(R3x::Workflow) do
          def self.name
            "Test"
          end
          trigger :schedule, cron: ""
        end
      end
    end

    test "trigger :rss rejects blank url" do
      assert_raises(ArgumentError) do
        Class.new(R3x::Workflow) do
          def self.name
            "Test"
          end
          trigger :rss, url: ""
        end
      end
    end

    test "supported_types returns list of available trigger files" do
      types = R3x::Triggers.supported_types
      assert_includes types, :rss
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
      assert_match(/Supported types:.*:rss.*:schedule/, error.message)
    end
  end
end

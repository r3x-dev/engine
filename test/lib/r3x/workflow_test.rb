require "test_helper"

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
      original_resolve = R3x::Triggers.method(:resolve)

      R3x::Triggers.define_singleton_method(:resolve) do |_type|
        R3x::TestSupport::FakeChangeDetectingTrigger
      end

      error = begin
        assert_raises(ArgumentError) do
          Class.new(R3x::Workflow::Base) do
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

    # uses :llm tests

    test "uses :llm with valid api_key declares capability and stores config" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::LlmWorkflow"
        end

        uses :llm, api_key: "GEMINI_API_KEY_MICHAL"
      end

      assert klass.uses?(:llm)
      assert_equal({ api_key: "GEMINI_API_KEY_MICHAL" }, klass.llm_config)
    end

    test "uses :llm without api_key raises" do
      error = assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Workflows::LlmNoKey"
          end

          uses :llm
        end
      end

      assert_match /requires api_key/, error.message
    end

    test "uses :llm with blank api_key raises" do
      error = assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Workflows::LlmBlankKey"
          end

          uses :llm, api_key: ""
        end
      end

      assert_match /requires api_key/, error.message
    end

    test "uses :llm with lowercase api_key raises" do
      error = assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Workflows::LlmLowercaseKey"
          end

          uses :llm, api_key: "gemini_api_key_michal"
        end
      end

      assert_match /Invalid api_key/, error.message
    end

    test "uses :llm with non-GEMINI_API_KEY prefix raises" do
      error = assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Workflows::LlmBadPrefix"
          end

          uses :llm, api_key: "OPENAI_KEY_TEST"
        end
      end

      assert_match /Invalid api_key/, error.message
    end

    test "uses :llm with special characters in api_key raises" do
      error = assert_raises(ArgumentError) do
        Class.new(R3x::Workflow::Base) do
          def self.name
            "Workflows::LlmInjection"
          end

          uses :llm, api_key: "GEMINI_API_KEY_TEST;INJECTED"
        end
      end

      assert_match /Invalid api_key/, error.message
    end

    test "uses :llm can coexist with other capabilities" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::MultiCap"
        end

        uses :networking
        uses :llm, api_key: "GEMINI_API_KEY_PROD"
      end

      assert klass.uses?(:networking)
      assert klass.uses?(:llm)
      assert_equal({ api_key: "GEMINI_API_KEY_PROD" }, klass.llm_config)
    end

    test "llm_config is nil when :llm not declared" do
      klass = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::NoLlm"
        end
      end

      assert_nil klass.llm_config
    end

    test "uses :llm config does not leak between subclasses" do
      parent = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::Parent"
        end

        uses :llm, api_key: "GEMINI_API_KEY_PARENT"
      end

      child = Class.new(R3x::Workflow::Base) do
        def self.name
          "Workflows::Child"
        end
      end

      assert_equal({ api_key: "GEMINI_API_KEY_PARENT" }, parent.llm_config)
      assert_nil child.llm_config
    end
  end
end

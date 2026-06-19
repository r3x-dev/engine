module R3x
  module Workflow
    module Dsl
      extend ActiveSupport::Concern

      Condition = Data.define(:predicate, :reason)

      class_methods do
        def inherited(subclass)
          super
          subclass._triggers = TriggerManager::Collection.new
          subclass._conditions = []
          subclass._completion_callbacks = []
        end

        def workflow_key
          name.demodulize.underscore
        end

        def trigger(type, **)
          trigger_instance = Triggers.resolve(type).new(**)
          trigger_instance.validate!(message_prefix: "Invalid trigger :#{type} for #{name}")
          _triggers.add(trigger_instance)
        end

        def condition(predicate, reason:)
          raise ArgumentError, "condition requires a predicate method name" if predicate.blank?
          raise ArgumentError, "condition requires a reason" if reason.blank?

          _conditions << Condition.new(predicate.to_sym, reason.to_s)
        end

        def on_complete(&block)
          raise ArgumentError, "on_complete requires a block" unless block

          _completion_callbacks << block
        end

        # Returns all triggers, with a default Manual trigger if none declared
        def triggers
          triggers = _triggers.to_a
          triggers.empty? ? [ Triggers::Manual.new ] : triggers
        end

        # Returns only explicitly declared triggers that support cron scheduling
        # Note: Uses _triggers directly to exclude auto-generated Manual triggers
        def schedulable_triggers
          _triggers.select(&:cron_schedulable?)
        end

        # Returns explicitly declared triggers indexed by unique_key
        # Note: Uses _triggers directly to exclude auto-generated Manual triggers
        def triggers_by_key
          _triggers.by_key
        end

        attr_accessor :_triggers
        attr_accessor :_conditions
        attr_accessor :_completion_callbacks
      end
    end
  end
end

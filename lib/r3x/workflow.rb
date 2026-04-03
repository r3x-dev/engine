module R3x
  module Workflow
    module Dsl
      extend ActiveSupport::Concern

      class_methods do
        def inherited(subclass)
          super
          subclass._triggers = TriggerManager::Collection.new
        end

        def workflow_key
          name.demodulize.underscore
        end

        def trigger(type, **options)
          trigger_instance = Triggers.resolve(type).new(**options)
          trigger_instance.validate!(message_prefix: "Invalid trigger :#{type} for #{name}")
          _triggers.add(trigger_instance)
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
      end
    end
  end
end

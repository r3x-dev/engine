module R3x
  class Workflow
    class << self
      def inherited(subclass)
        super
        subclass._triggers = TriggerCollection.new
      end

      def workflow_key
        name.demodulize.underscore
      end

      def trigger(type, **options)
        trigger_instance = Triggers.resolve(type).new(**options)
        trigger_instance.validate!(message_prefix: "Invalid trigger :#{type} for #{name}")
        _triggers.add(trigger_instance)
      end

      def triggers
        _triggers.to_a
      end

      def schedulable_triggers
        _triggers.select(&:cron_schedulable?)
      end

      def triggers_by_key
        _triggers.by_key
      end

      attr_accessor :_triggers
    end

    def run(ctx)
      raise NotImplementedError, "Workflow must implement #run(ctx)"
    end
  end
end

module R3x
  class Workflow
    class << self
      def inherited(subclass)
        subclass.instance_variable_set(:@_triggers, [])
      end

      def workflow_key
        name.demodulize.underscore
      end

      def trigger(type, **options)
        trigger_class = Triggers.resolve(type)
        trigger_instance = trigger_class.new(**options)

        trigger_instance.validate!(message_prefix: "Invalid trigger :#{type} for #{name}")
        @_triggers << trigger_instance
      end

      def triggers
        @_triggers ||= []
        @_triggers.dup
      end

      def schedulable_triggers
        triggers.select { |t| t.respond_to?(:cron_schedulable?) && t.cron_schedulable? }
      end
    end

    def run(ctx)
      raise NotImplementedError, "Workflow must implement #run(ctx)"
    end
  end
end

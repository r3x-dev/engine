module R3x
  module TriggerManager
    class Execution
      attr_reader :trigger, :workflow_key, :payload

      def initialize(trigger:, workflow_key:, payload: nil)
        @trigger = trigger
        @workflow_key = workflow_key
        @payload = payload
      end

      def type
        @trigger.type
      end

      def method_missing(name, *args, &block)
        if name.to_s.end_with?("?")
          type_name = name.to_s.chomp("?").to_sym
          return @trigger.type == type_name
        end
        super
      end

      def respond_to_missing?(name, include_private = false)
        name.to_s.end_with?("?")
      end

      def options
        @trigger.options
      end
    end
  end
end

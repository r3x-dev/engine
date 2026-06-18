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

      def manual?
        type == :manual
      end

      def schedule?
        type == :schedule
      end

      def options
        @trigger.options
      end
    end
  end
end

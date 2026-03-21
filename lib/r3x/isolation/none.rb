module R3x
  module Isolation
    class None < Base
      def self.run(workflow_class, context, trigger_key: nil, trigger_payload: nil, **)
        workflow_class.perform_now(trigger_key, trigger_payload: trigger_payload)
      end
    end
  end
end

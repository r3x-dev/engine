module R3x
  module Workflow
    module Registry
      extend self

      MUTEX = Mutex.new
      REGISTRATIONS = Concurrent::Map.new

      def register(workflow_class)
        MUTEX.synchronize do
          key = workflow_class.workflow_key.to_s
          REGISTRATIONS[key] = workflow_class
        end
      end

      def fetch(workflow_key)
        REGISTRATIONS.fetch(workflow_key.to_s)
      end

      def all
        REGISTRATIONS.values.sort_by(&:workflow_key)
      end

      def reset!
        MUTEX.synchronize do
          REGISTRATIONS.clear
        end
      end
    end
  end
end

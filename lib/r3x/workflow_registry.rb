module R3x
  class WorkflowRegistry
    class << self
      def register(workflow_class)
        mutex.synchronize do
          key = workflow_class.workflow_key.to_s
          registrations[key] = workflow_class
        end
      end

      def fetch(workflow_key)
        registrations.fetch(workflow_key.to_s)
      end

      def all
        registrations.values.sort_by(&:workflow_key)
      end

      def reset!
        mutex.synchronize do
          @registrations = {}
        end
      end

      private

      def registrations
        @registrations ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end

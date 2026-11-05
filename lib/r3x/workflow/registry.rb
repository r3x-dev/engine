# frozen_string_literal: true

module R3x
  module Workflow
    module Registry
      extend self

      MUTEX = Mutex.new
      REGISTRATIONS = {} # rubocop:disable Style/MutableConstant -- All access is guarded by MUTEX.

      def register(workflow_class)
        MUTEX.synchronize do
          key = workflow_class.workflow_key.to_s
          REGISTRATIONS[key] = workflow_class
        end
      end

      def fetch(workflow_key)
        MUTEX.synchronize { REGISTRATIONS.fetch(workflow_key.to_s) }
      end

      def all
        MUTEX.synchronize { REGISTRATIONS.values }.sort_by(&:workflow_key)
      end

      def replace!(workflow_classes)
        registrations = workflow_classes.index_by { |workflow_class| workflow_class.workflow_key.to_s }
        MUTEX.synchronize { REGISTRATIONS.replace(registrations) }
      end

      def reset!
        MUTEX.synchronize { REGISTRATIONS.clear }
      end
    end
  end
end

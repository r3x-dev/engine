module R3x
  module Workflow
    class Base < ApplicationJob
      include ActiveJob::Continuable
      include Dsl
      include R3x::Concerns::Logger

      class << self
        def method_added(method_name)
          if method_name == :perform && self != Base
            raise ArgumentError, "Do not override #perform in #{name}. Override #run(ctx) instead."
          end
          super
        end
      end

      def perform(trigger_key = nil, trigger_payload: nil)
        ctx = R3x::Workflow::Executor.build_context(
          workflow_class: self.class,
          trigger_key: trigger_key,
          trigger_payload: trigger_payload
        )

        run(ctx)
      end

      def run(ctx)
        raise NotImplementedError, "#{self.class.name} must implement #run(ctx)"
      end
    end
  end
end

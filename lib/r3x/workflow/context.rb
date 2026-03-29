# frozen_string_literal: true

module R3x
  module Workflow
    class Context
      include R3x::Concerns::Logger

      attr_reader :trigger, :execution, :workflow_class

      def initialize(trigger:, workflow_key:, workflow_class: nil)
        @trigger = trigger
        @workflow_class = workflow_class
        @execution = Execution.new(workflow_key: workflow_key)
      end

      def client
        @client ||= Client
      end
    end
  end
end

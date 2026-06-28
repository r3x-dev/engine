# frozen_string_literal: true

module Workflows
  class ContinuableWorkflow < R3x::Workflow::Base
    EVENTS = Concurrent::Array.new

    self.resume_options = { wait: 2.minutes }

    trigger :manual
    on_complete { self.class.events << "complete" }

    class << self
      def events
        EVENTS
      end

      def reset_events!
        EVENTS.clear
      end
    end

    def run
      step :first do
        self.class.events << "first"
      end

      step :second, isolated: true do
        self.class.events << "second"
      end

      step :third, isolated: true do
        self.class.events << "third"
      end

      { "events" => self.class.events.dup }
    end
  end
end

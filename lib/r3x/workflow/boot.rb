# frozen_string_literal: true

module R3x
  module Workflow
    module Boot
      extend self

      def load!
        PackLoader.load!
      end

      def load_and_schedule!
        load!
        RecurringTasksConfig.schedule_all!
      end
    end
  end
end

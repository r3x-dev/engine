module R3x
  module Workflow
    module Boot
      extend self

      def load!
        PackLoader.load!
      end

      def load_and_schedule!
        load!
        schedule_all!
      end

      private

      def schedule_all!
        RecurringTasksConfig.schedule_all!
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
        Rails.logger.warn("SolidQueue tables not available, skipping dynamic recurring task scheduling")
      end
    end
  end
end

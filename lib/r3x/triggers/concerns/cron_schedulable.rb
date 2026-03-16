module R3x
  module Triggers
    module Concerns
      module CronSchedulable
        def cron_schedulable?
          true
        end

        def cron
          raise NotImplementedError, "#{self.class.name} must implement #cron"
        end
      end
    end
  end
end

module R3x
  module Triggers
    module Concerns
      module CronSchedulable
        extend ActiveSupport::Concern

        included do
          validates :cron, presence: true
          validates_with Validators::Cron
        end

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

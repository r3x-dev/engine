module R3x
  module Triggers
    module Concerns
      module CronSchedulable
        extend ActiveSupport::Concern

        included do
          validates :cron, presence: true
          validates_with Validators::Cron
          validates_with Validators::Timezone, timezone_field: :timezone
        end

        def cron_schedulable?
          true
        end

        def cron
          raise NotImplementedError, "#{self.class.name} must implement #cron"
        end

        def timezone
          nil
        end

        def schedule
          [ cron, timezone ].compact.join(" ")
        end
      end
    end
  end
end

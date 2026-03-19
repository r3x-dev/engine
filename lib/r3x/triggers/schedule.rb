module R3x
  module Triggers
    class Schedule < Base
      include Concerns::CronSchedulable

      validates :cron, presence: true
      validates_with Validators::Cron

      def initialize(cron: nil, **options)
        normalized_cron = cron.is_a?(String) ? cron.strip : cron
        super(:schedule, cron: normalized_cron, **options)
      end

      def cron
        options[:cron]
      end
    end
  end
end

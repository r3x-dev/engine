module R3x
  module Triggers
    class Schedule < Base
      def initialize(cron: nil, **options)
        super(:schedule, cron: cron, **options)
      end

      def cron
        options[:cron]
      end

      def validate!
        unless cron
          raise ArgumentError, "trigger :schedule requires a 'cron' option (e.g., cron: '0 13 * * *' or cron: 'every day at 13:00')"
        end

        Validators::Cron.validate!(cron, field_name: "cron")
      end

      def to_h
        { type: :schedule, cron: cron }
      end
    end
  end
end

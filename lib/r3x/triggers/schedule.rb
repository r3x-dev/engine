module R3x
  module Triggers
    class Schedule < Base
      include Concerns::CronSchedulable

      validate :validate_timezone_sources
      validate :validate_default_timezone, if: :uses_default_timezone?

      def initialize(cron: nil, timezone: nil, **options)
        normalized_cron = cron.is_a?(String) ? cron.strip : cron
        normalized_timezone = if timezone.is_a?(String)
          (Validators::Timezone.resolve(timezone) || timezone.strip).presence
        else
          timezone
        end

        trigger_options = options.dup
        trigger_options[:timezone] = normalized_timezone if normalized_timezone.present?

        super(:schedule, cron: normalized_cron, **trigger_options)
      end

      def cron
        options[:cron]
      end

      def timezone
        options[:timezone] || inline_timezone || default_timezone
      end

      def schedule
        return cron if inline_timezone.present?

        super
      end

      private

      def validate_timezone_sources
        return if options[:timezone].blank? || inline_timezone.blank?

        errors.add(:timezone, "use either timezone: or a timezone embedded in cron, not both")
      end

      def validate_default_timezone
        default_timezone
      rescue ArgumentError => e
        errors.add(:timezone, e.message)
      end

      def uses_default_timezone?
        options[:timezone].blank? && inline_timezone.blank? && default_timezone_name.present?
      end

      def inline_timezone
        timezone_name = parsed_cron&.zone
        Validators::Timezone.normalize(timezone_name) if timezone_name.present?
      rescue ArgumentError
        nil
      end

      def parsed_cron
        return if cron.blank?

        parsed = Fugit.parse(cron, multi: :fail)
        parsed if parsed.is_a?(Fugit::Cron)
      rescue ArgumentError
        nil
      end

      def default_timezone_name
        R3x::Env.fetch("R3X_TIMEZONE")
      end

      def default_timezone
        timezone_name = default_timezone_name
        Validators::Timezone.normalize(timezone_name) if timezone_name
      end
    end
  end
end

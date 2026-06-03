module R3x
  module TestSupport
    class FakeChangeDetectingTrigger < R3x::Triggers::Base
      include R3x::Triggers::Concerns::CronSchedulable
      include R3x::Triggers::Concerns::ChangeDetecting

      def initialize(identity:, cron: "every 15 minutes", detector: nil, **options)
        @detector = detector || ->(workflow_key:, state:) { { changed: false, state: state, payload: nil } }
        super(:fake_change_detecting, identity: identity, cron: cron, **options)
      end

      def validate!(**)
        true
      end

      def cron
        options[:cron]
      end

      def unique_key
        # Identity-based key - doesn't change when cron changes
        "fake_change_detecting:#{options[:identity]}"
      end

      def detect_changes(workflow_key:, state:)
        @detector.call(workflow_key:, state:)
      end
    end
  end
end

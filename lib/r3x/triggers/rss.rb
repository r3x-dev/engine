module R3x
  module Triggers
    class Rss < Base
      DEFAULT_EVERY = "every hour"

      def initialize(url:, every: DEFAULT_EVERY, **options)
        super(:rss, url: url, every: every, **options)
      end

      def url
        options[:url]
      end

      def every
        options[:every]
      end

      def validate!
        unless url
          raise ArgumentError, "trigger :rss requires a 'url' option"
        end

        Validators::Url.validate!(url, field_name: "url")
        Validators::Cron.validate!(every, field_name: "every")
      end

      def to_h
        { type: :rss, url: url, every: every }
      end
    end
  end
end

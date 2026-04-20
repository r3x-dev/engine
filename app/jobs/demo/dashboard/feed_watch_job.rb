module Demo
  module Dashboard
    class FeedWatchJob < BaseJob
      queue_as :feeds
    end
  end
end

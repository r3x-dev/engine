module Demo
  module Dashboard
    class VendorFeedWatchJob < BaseJob
      queue_as :feeds
    end
  end
end

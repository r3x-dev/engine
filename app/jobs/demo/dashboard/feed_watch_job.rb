# frozen_string_literal: true

module Demo
  module Dashboard
    class FeedWatchJob < BaseJob
      queue_as :feeds
    end
  end
end

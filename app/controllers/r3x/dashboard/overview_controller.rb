module R3x
  module Dashboard
    class OverviewController < ApplicationController
      def index
        overview = Overview.new

        @summary_cards = overview.summary_cards
        @needs_attention = overview.needs_attention
        @recent_runs = overview.recent_runs
      end
    end
  end
end

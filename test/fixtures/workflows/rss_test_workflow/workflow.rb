module Workflows
  class RssTestWorkflow < R3x::Workflow::Base
    trigger :rss, url: "https://example.com/feed.xml", cron: "every 15 minutes"

    def run(ctx)
      ctx.trigger.payload
    end
  end
end

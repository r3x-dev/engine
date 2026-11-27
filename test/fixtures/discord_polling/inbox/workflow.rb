# frozen_string_literal: true

module Workflows
  class Inbox < R3x::Workflow::Base
    trigger :discord_message, key: :images, channel_id: "42", attachments: :images, run_per: :message
  end
end

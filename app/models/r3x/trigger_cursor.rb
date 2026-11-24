# frozen_string_literal: true

module R3x
  class TriggerCursor < ApplicationRecord
    def self.seed!(workflow_key:, trigger_key:, message_id:)
      insert({ workflow_key:, trigger_key:, message_id: }, unique_by: %i[workflow_key trigger_key], returning: false)
    end

    def advance(from:, to:)
      transaction(requires_new: true) do
        # Claim the next message before enqueueing on the same database connection.
        updated = self.class.where(id:, message_id: from).update_all(message_id: to)
        next false if updated.zero?

        yield
        true
      end || false
    end
  end
end

module R3x
  class TriggerState < ApplicationRecord
    serialize :state, coder: MultiJson if connection.adapter_name.downcase == "sqlite"

    validates :workflow_key, presence: true
    validates :trigger_type, presence: true
    validates :trigger_key, presence: true, uniqueness: { scope: :workflow_key }

    def record_check!(result)
      update!(
        state: result.fetch(:state),
        last_checked_at: Time.current,
        last_error_at: nil,
        last_error_message: nil,
        last_triggered_at: result[:changed] ? Time.current : last_triggered_at
      )
    end

    def record_error!(error)
      update!(
        last_error_at: Time.current,
        last_error_message: error.message
      )
    end
  end
end

# frozen_string_literal: true

module Demo
  module Dashboard
    class InvoiceDispatchJob < BaseJob
      queue_as :mailers
    end
  end
end

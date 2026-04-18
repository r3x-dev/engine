module Demo
  module Dashboard
    class InvoiceDispatchJob < BaseJob
      queue_as :mailers
    end
  end
end

module Demo
  module Dashboard
    class InventorySyncJob < BaseJob
      queue_as :low
    end
  end
end

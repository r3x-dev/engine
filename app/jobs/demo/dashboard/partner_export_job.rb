module Demo
  module Dashboard
    class PartnerExportJob < BaseJob
      queue_as :critical
    end
  end
end

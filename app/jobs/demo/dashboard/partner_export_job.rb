# frozen_string_literal: true

module Demo
  module Dashboard
    class PartnerExportJob < BaseJob
      queue_as :critical
    end
  end
end

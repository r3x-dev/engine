module Demo
  module Dashboard
    class BaseJob < ActiveJob::Base
      def perform(*)
      end
    end
  end
end

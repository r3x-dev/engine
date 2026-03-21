module R3x
  module Isolation
    class None < Base
      def self.run(workflow_class, context, **)
        workflow_class.new.run(context)
      end
    end
  end
end

module R3x
  module Isolation
    class Base
      def self.run(workflow_class, context, **options)
        raise NotImplementedError
      end
    end
  end
end

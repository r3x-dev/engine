module R3x
  module Workflow
    class Base
      include Dsl
      include R3x::Concerns::Logger

      def run(ctx)
        raise NotImplementedError, "Workflow must implement #run(ctx)"
      end
    end
  end
end

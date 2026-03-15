# Provides a tagged logger to any class that includes it.
# The logger is automatically tagged with the class name.
#
# Usage:
#   class MyClass
#     include R3x::Concerns::Logger
#
#     def do_something
#       logger.info("message")  # => [MyClass] message
#     end
#   end
#
module R3x
  module Concerns
    module Logger
      extend ActiveSupport::Concern

      included do
        def logger
          @logger ||= ActiveSupport::TaggedLogging.new(Rails.logger).tagged(self.class.name)
        end
      end
    end
  end
end

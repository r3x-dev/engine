# Provides a tagged logger to any class that includes or extends it.
# The logger is automatically tagged with the class name and prefers the
# current execution logger when a workflow or job is running.
#
# Usage (instance methods):
#   class MyClass
#     include R3x::Concerns::Logger
#
#     def do_something
#       logger.info("message")  # tagged via the current execution logger with the class name
#     end
#   end
#
# Usage (class methods):
#   class MyClass
#     extend R3x::Concerns::Logger
#
#     def self.do_something
#       logger.info("message")  # tagged via the current execution logger with the class name
#     end
#   end
#
module R3x
  module Concerns
    module Logger
      extend ActiveSupport::Concern

      class_methods do
        def logger
          current_logger.tagged(name)
        end

        private

        def current_logger
          R3x::ExecutionLogger.current
        end
      end

      def logger
        current_logger.tagged(logger_tag_name)
      end

      private

      def current_logger
        R3x::ExecutionLogger.current
      end

      def logger_tag_name
        self.is_a?(Module) ? name : self.class.name
      end
    end
  end
end

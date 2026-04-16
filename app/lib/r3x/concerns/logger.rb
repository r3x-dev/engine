# Provides a tagged logger to any class that includes or extends it.
# The logger is automatically tagged with the class name.
#
# Usage (instance methods):
#   class MyClass
#     include R3x::Concerns::Logger
#
#     def do_something
#       logger.info("message")  # => [MyClass] message
#     end
#   end
#
# Usage (class methods):
#   class MyClass
#     extend R3x::Concerns::Logger
#
#     def self.do_something
#       logger.info("message")  # => [MyClass] message
#     end
#   end
#
module R3x
  module Concerns
    module Logger
      extend ActiveSupport::Concern

      class_methods do
        def logger
          Rails.logger.tagged(name)
        end
      end

      def logger
        Rails.logger.tagged(logger_tag_name)
      end

      private

      def logger_tag_name
        self.is_a?(Module) ? name : self.class.name
      end
    end
  end
end

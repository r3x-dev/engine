module R3x
  module ExecutionLogger
    KEY = :r3x_execution_logger
    private_constant :KEY

    class << self
      def with(logger)
        previous_logger = stored_logger
        ActiveSupport::IsolatedExecutionState[KEY] = logger
        yield
      ensure
        ActiveSupport::IsolatedExecutionState[KEY] = previous_logger
      end

      def current
        stored_logger || Rails.logger
      end

      private

      def stored_logger
        ActiveSupport::IsolatedExecutionState[KEY]
      end
    end
  end
end

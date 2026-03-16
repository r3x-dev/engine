module R3x
  class WorkflowContext
    include R3x::Concerns::Logger

    attr_reader :triggered_by

    def self.build
      builder = Builder.new
      yield(builder) if block_given?
      builder.to_context
    end

    def initialize(triggered_by:, previous_run_at_fetcher: nil)
      @triggered_by = triggered_by
      @previous_run_at_fetcher = previous_run_at_fetcher
    end

    def previous_run_at
      return @previous_run_at if defined?(@previous_run_at)

      @previous_run_at = @previous_run_at_fetcher&.call
    end

    def first_run?
      previous_run_at.nil?
    end

    def fetch_body(url)
      http_client.get(url)
    end

    def discord_output
      @discord_output ||= R3x::Outputs::Discord.new
    end

    class Builder
      attr_accessor :triggered_by, :previous_run_at_fetcher

      def initialize
        @triggered_by = nil
        @previous_run_at_fetcher = nil
      end

      def with_solid_queue_task(workflow_key)
        @previous_run_at_fetcher = -> {
          SolidQueue::RecurringTask.find_by(key: workflow_key)&.last_enqueued_time
        }
        self
      end

      def to_context
        raise ArgumentError, "triggered_by is required" if @triggered_by.nil?

        WorkflowContext.new(
          triggered_by: @triggered_by,
          previous_run_at_fetcher: @previous_run_at_fetcher
        )
      end
    end

    private

    def http_client
      @http_client ||= R3x::Services::HttpClient.new
    end
  end
end

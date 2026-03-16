module R3x
  class WorkflowContext
    include R3x::Concerns::Logger

    attr_reader :trigger

    def self.build
      builder = Builder.new
      yield(builder) if block_given?
      builder.to_context
    end

    def initialize(trigger:)
      @trigger = trigger
    end

    def fetch_body(url)
      http_client.get(url)
    end

    def discord_output
      @discord_output ||= R3x::Outputs::Discord.new
    end

    class Builder
      attr_accessor :trigger_type, :previous_run_at_fetcher

      def initialize
        @trigger_type = nil
        @previous_run_at_fetcher = nil
      end

      def with_solid_queue_task(workflow_key)
        @previous_run_at_fetcher = -> {
          SolidQueue::RecurringTask.find_by(key: workflow_key)&.last_enqueued_time
        }
        self
      end

      def to_context
        raise ArgumentError, "trigger_type is required" if @trigger_type.nil?

        trigger = TriggerInfo.new(@trigger_type, previous_run_at_fetcher: @previous_run_at_fetcher)
        WorkflowContext.new(trigger: trigger)
      end
    end

    private

    def http_client
      @http_client ||= R3x::Services::HttpClient.new
    end
  end
end

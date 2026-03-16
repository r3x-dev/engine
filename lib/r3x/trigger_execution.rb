module R3x
  class TriggerExecution
    attr_reader :trigger, :workflow_key

    def initialize(trigger:, workflow_key:)
      @trigger = trigger
      @workflow_key = workflow_key
    end

    def type
      @trigger.type
    end

    def method_missing(name, *args, &block)
      if name.to_s.end_with?("?")
        type_name = name.to_s.chomp("?").to_sym
        return @trigger.type == type_name
      end
      super
    end

    def respond_to_missing?(name, include_private = false)
      name.to_s.end_with?("?")
    end

    def options
      @trigger.options
    end
  end
end

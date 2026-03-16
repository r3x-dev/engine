module R3x
  class TriggerInfo
    attr_reader :type

    def initialize(type, previous_run_at_fetcher: nil)
      @type = type.to_sym
      @previous_run_at_fetcher = previous_run_at_fetcher
    end

    def method_missing(name, *args, &block)
      if name.to_s.end_with?("?")
        type_name = name.to_s.chomp("?").to_sym
        return @type == type_name
      end
      super
    end

    def respond_to_missing?(name, include_private = false)
      name.to_s.end_with?("?")
    end

    def previous_run_at
      return nil unless schedule?
      return @previous_run_at if defined?(@previous_run_at)

      @previous_run_at = @previous_run_at_fetcher&.call
    end

    def first_run?
      previous_run_at.nil?
    end
  end
end

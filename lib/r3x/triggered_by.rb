module R3x
  class TriggeredBy
    attr_reader :type

    def initialize(type)
      @type = type.to_sym
    end

    def schedule?
      type == :schedule
    end

    def rss?
      type == :rss
    end

    def manual?
      type == :manual
    end

    def ==(other)
      return type == other if other.is_a?(Symbol)
      return type == other.type if other.is_a?(TriggeredBy)
      false
    end
  end
end

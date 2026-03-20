module R3x
  module TriggerManager
    class Collection
      include Enumerable

      def initialize
        @by_key = {}
      end

      def add(trigger)
        key = trigger.unique_key
        raise ArgumentError, "Trigger with key '#{key}' already exists" if @by_key.key?(key)
        @by_key[key] = trigger
      end

      def each(&block)
        @by_key.values.each(&block)
      end

      def by_key
        @by_key.dup
      end

      def select(&block)
        @by_key.values.select(&block)
      end

      def to_a
        @by_key.values
      end

      def size
        @by_key.size
      end
    end
  end
end

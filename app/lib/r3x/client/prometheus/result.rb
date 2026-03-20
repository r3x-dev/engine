module R3x
  module Client
    class Prometheus
      class Result
        include Enumerable

        attr_reader :result_type

        def initialize(data)
          @result_type = data["resultType"]
          @series = data.fetch("result", []).map { |s| Series.new(s) }
        end

        def each(&block)
          series.each(&block)
        end

        private

        attr_reader :series

        Series = Struct.new(:data) do
          def metric
            data["metric"]
          end

          def value
            data.dig("value", 1)
          end

          def timestamp
            data.dig("value", 0)
          end
        end
      end
    end
  end
end

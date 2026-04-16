module R3x
  module Dashboard
    class JobPayload
      def initialize(raw_arguments)
        @raw_arguments = normalize_argument(raw_arguments)
      end

      def workflow_arguments
        @workflow_arguments ||= if serialized_active_job?
          Array(fetch_key(raw_arguments, "arguments"))
        else
          Array(raw_arguments)
        end
      end

      def options
        candidate = workflow_arguments.second
        candidate.is_a?(Hash) ? candidate : {}
      end

      def legacy_workflow_key
        candidate = workflow_arguments.first
        return candidate if candidate.is_a?(String) && candidate.present?

        nil
      end

      def trigger_payload
        options["trigger_payload"] || options[:trigger_payload]
      end

      private
        attr_reader :raw_arguments

        def serialized_active_job?
          raw_arguments.is_a?(Hash) && fetch_key(raw_arguments, "job_class").present? && raw_arguments.key?("arguments")
        end

        def fetch_key(hash, key)
          hash[key] || hash[key.to_sym]
        end

        def normalize_argument(argument)
          case argument
          when Array
            argument.map { |item| normalize_argument(item) }
          when Hash
            normalize_hash(argument)
          else
            argument
          end
        end

        def normalize_hash(argument)
          argument.each_with_object({}) do |(key, value), normalized|
            normalized[key] = normalize_argument(value)
          end.tap do |normalized|
            symbolize_marked_keys!(normalized, "_aj_ruby2_keywords")
            symbolize_marked_keys!(normalized, "_aj_symbol_keys")
          end
        end

        def symbolize_marked_keys!(hash, marker)
          Array(hash.delete(marker)).each do |key|
            next unless hash.key?(key)

            hash[key.to_sym] = hash.delete(key)
          end
        end
    end
  end
end

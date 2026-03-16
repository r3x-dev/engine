require_relative "triggers/base"

module R3x
  class Workflow
    class << self
      def inherited(subclass)
        subclass.instance_variable_set(:@_triggers, [])
      end

      def workflow_key
        name.demodulize.underscore
      end

      def trigger(type, **options)
        trigger_class = resolve_trigger_class(type)
        trigger_instance = trigger_class.new(**options)

        trigger_instance.validate!
        @_triggers << trigger_instance
      end

      def triggers
        @_triggers ||= []
        @_triggers.dup
      end

      def supported_trigger_types
        triggers_dir = File.expand_path("triggers", __dir__)
        Dir.glob(File.join(triggers_dir, "*.rb")).filter_map do |file|
          basename = File.basename(file, ".rb")
          next if basename == "base"
          basename.to_sym
        end.sort
      end

      def schedule_trigger
        triggers.find { |t| t.type == :schedule }
      end

      def rss_triggers
        triggers.select { |t| t.type == :rss }
      end

      private

      def resolve_trigger_class(type)
        type_sym = type.to_sym
        supported = supported_trigger_types

        unless supported.include?(type_sym)
          raise ArgumentError, "Unknown trigger type: #{type}. No file found for trigger '#{type_sym}.rb' in #{File.expand_path("triggers", __dir__)}. " \
                               "Supported types: #{supported.map { |t| ":#{t}" }.join(", ")}"
        end

        class_name = type.to_s.camelize
        full_class_name = "::R3x::Triggers::#{class_name}"

        begin
          full_class_name.constantize
        rescue NameError
          raise ArgumentError, "Trigger file '#{type_sym}.rb' exists but class #{full_class_name} is not defined or failed to load."
        end
      end
    end

    def run(ctx)
      raise NotImplementedError, "Workflow must implement #run(ctx)"
    end
  end
end

module R3x
  module Triggers
    class << self
      def supported_types
        trigger_files.filter_map do |file|
          basename = File.basename(file, ".rb")
          next if basename == "base"
          basename.to_sym
        end.sort
      end

      def resolve(type)
        type_sym = type.to_sym
        supported = supported_types

        unless supported.include?(type_sym)
          raise ArgumentError, "Unknown trigger type: #{type}. No file found for trigger '#{type_sym}.rb' in #{triggers_dir}. " \
                               "Supported types: #{supported.map { |t| ":#{t}" }.join(", ")}"
        end

        full_class_name = "::R3x::Triggers::#{type.to_s.camelize}"

        begin
          full_class_name.constantize
        rescue NameError
          raise ArgumentError, "Trigger file '#{type_sym}.rb' exists but class #{full_class_name} is not defined or failed to load."
        end
      end

      private

      def triggers_dir
        File.expand_path("triggers", __dir__)
      end

      def trigger_files
        Dir.glob(File.join(triggers_dir, "*.rb"))
      end
    end
  end
end

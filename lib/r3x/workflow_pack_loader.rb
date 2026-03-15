module R3x
  class WorkflowPackLoader
    class << self
      def load!(force: false)
        mutex.synchronize do
          return if @loaded && !force

          R3x::WorkflowRegistry.reset!
          workflow_files.each do |entrypoint|
            require entrypoint
            register_workflow(entrypoint)
          end
          @loaded = true
        end
      end

      private

      def workflow_files
        ENV.fetch("R3X_WORKFLOW_PATHS", "").split(File::PATH_SEPARATOR).flat_map do |path|
          base = File.expand_path(path.strip)
          next [] unless File.directory?(base)

          files = []
          # Root level workflow.rb
          root_workflow = File.join(base, "workflow.rb")
          files << root_workflow if File.file?(root_workflow)

          # First-level subdirectories only (faster than glob)
          Dir.foreach(base) do |entry|
            next if entry.start_with?(".")
            subdir = File.join(base, entry)
            if File.directory?(subdir)
              workflow_file = File.join(subdir, "workflow.rb")
              files << workflow_file if File.file?(workflow_file)
            end
          end

          files
        end.uniq
      end

      def register_workflow(entrypoint_file)
        dir_name = File.basename(File.dirname(entrypoint_file))
        class_name = "Workflows::#{dir_name.camelize}"
        workflow_class = class_name.constantize
        R3x::WorkflowRegistry.register(workflow_class)
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end

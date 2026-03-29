module R3x
  module Workflow
    class PackLoader
      WORKFLOW_ENTRYPOINT_FILENAME = "workflow.rb"

      class << self
        def load!(force: false)
          mutex.synchronize do
            return if @loaded && !force

            R3x::Workflow::Registry.reset!
            workflow_files.each do |entrypoint|
              R3x::Workflow::Validator.scan_file(entrypoint)
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
            root_workflow = File.join(base, WORKFLOW_ENTRYPOINT_FILENAME)
            files << root_workflow if File.file?(root_workflow)

            Dir.foreach(base) do |entry|
              next if entry.start_with?(".")
              subdir = File.join(base, entry)
              if File.directory?(subdir)
                workflow_file = File.join(subdir, WORKFLOW_ENTRYPOINT_FILENAME)
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
          R3x::Workflow::Registry.register(workflow_class)
        end

        def mutex
          @mutex ||= Mutex.new
        end
      end
    end
  end
end

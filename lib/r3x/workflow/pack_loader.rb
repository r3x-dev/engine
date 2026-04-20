module R3x
  module Workflow
    module PackLoader
      extend self
      extend R3x::Concerns::Logger

      WORKFLOW_ENTRYPOINT_FILENAME = "workflow.rb"
      MUTEX = Mutex.new
      LOADED = Concurrent::AtomicBoolean.new(false)

      def load!(force: false)
        MUTEX.synchronize do
          return if LOADED.true? && !force

          R3x::Workflow::Registry.reset!
          loaded = []

          workflow_files.each do |entrypoint|
            ensure_legacy_llm_schema_support(entrypoint)
            require entrypoint
            workflow_class = register_workflow(entrypoint)
            loaded << workflow_class

            Rails.logger.tagged("r3x.workflow_key=#{workflow_class.workflow_key}") do
              logger.info "Loaded workflow class=#{workflow_class.name} entrypoint=#{entrypoint}"
            end
          rescue => e
            Rails.logger.tagged("r3x.workflow_entrypoint=#{entrypoint}") do
              logger.error "Workflow load failed error_class=#{e.class} error_message=#{e.message}"
            end

            raise
          end

          logger.info "Loaded #{loaded.size} workflow packs"
          LOADED.make_true
        end
      end

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

      def ensure_legacy_llm_schema_support(entrypoint)
        return unless File.read(entrypoint).include?("RubyLLM::Schema")

        R3x::GemLoader.require("ruby_llm/schema")
      end

      def register_workflow(entrypoint_file)
        dir_name = File.basename(File.dirname(entrypoint_file))
        class_name = "Workflows::#{dir_name.camelize}"
        workflow_class = class_name.constantize
        R3x::Workflow::Registry.register(workflow_class)
        workflow_class
      end
    end
  end
end

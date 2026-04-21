require "amazing_print"

module R3x
  module Workflow
    class Cli
      def initialize(stdout: $stdout, pack_loader: PackLoader, registry: Registry)
        @stdout = stdout
        @pack_loader = pack_loader
        @registry = registry
      end

      def run(path, dry_run: false, skip_cache: false)
        stdout.puts run_message(path, dry_run:, skip_cache:)

        result = with_run_env(dry_run:, skip_cache:) do
          load_workflow(path).new.perform
        end

        print_result(result)
        result
      end

      def list
        pack_loader.load!
        workflows = registry.all

        if workflows.empty?
          stdout.puts "No workflows found."
          return workflows
        end

        stdout.puts "Available workflows:"
        workflows.each do |workflow|
          stdout.puts "  #{workflow.workflow_key}  (triggers: #{trigger_types_for(workflow)})"
        end

        workflows
      end

      def info(key)
        pack_loader.load!
        workflow_class = registry.fetch(key)

        stdout.puts "Workflow: #{key}"
        stdout.puts "  Class:    #{workflow_class}"
        stdout.puts "  Triggers:"
        workflow_class.triggers.each do |trigger|
          stdout.puts "    #{trigger.type}  key=#{trigger.unique_key}"
        end

        workflow_class
      end

      private

      attr_reader :pack_loader, :registry, :stdout

      def load_workflow(path)
        full_path = workflow_file_path(path)
        require full_path

        workflow = ObjectSpace.each_object(Class).find do |klass|
          klass < R3x::Workflow::Base &&
            klass.name.present? &&
            Object.const_source_location(klass.name)&.first == full_path
        end
        raise ArgumentError, "No workflow class found in #{path}" unless workflow

        workflow
      end

      def print_result(result)
        if result.is_a?(String)
          stdout.puts result
        else
          stdout.puts result.ai
        end
      end

      def run_message(path, dry_run:, skip_cache:)
        return "Dry run without cache: #{path}" if dry_run && skip_cache
        return "Dry run: #{path}" if dry_run
        return "Running without cache: #{path}" if skip_cache

        "Running: #{path}"
      end

      def trigger_types_for(workflow)
        workflow.triggers.map(&:type).uniq.join(", ")
      end

      def workflow_file_path(path)
        full_path = File.expand_path(path)
        raise ArgumentError, "Workflow file not found: #{path}" unless File.exist?(full_path)
        raise ArgumentError, "Not a file: #{path}" unless File.file?(full_path)

        full_path
      end

      def with_run_env(dry_run:, skip_cache:)
        overrides = {}
        overrides["R3X_DRY_RUN"] = "true" if dry_run
        overrides["R3X_SKIP_CACHE"] = "true" if skip_cache

        originals = overrides.keys.each_with_object({}) { |key, memo| memo[key] = ENV[key] }

        overrides.each do |key, value|
          ENV[key] = value
        end

        yield
      ensure
        originals&.each do |key, value|
          value.nil? ? ENV.delete(key) : ENV[key] = value
        end
      end
    end
  end
end

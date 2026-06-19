# frozen_string_literal: true

module R3x
  module Workflow
    class Cli
      def initialize(stdout: $stdout, pack_loader: PackLoader, registry: Registry)
        @stdout = stdout
        @pack_loader = pack_loader
        @registry = registry
      end

      def run(path, dry_run: nil, skip_cache: false)
        with_run_env(dry_run:, skip_cache:) do
          stdout.puts run_message(path, dry_run_explicit: dry_run == true)
          load_workflow(path).new.perform
        end
      end

      def list
        pack_loader.load!
        workflows = registry.all

        if workflows.empty?
          stdout.puts "No workflows found."
          return workflows
        end

        stdout.puts "Available workflows:"
        workflows.each { |workflow| stdout.puts "  #{workflow.workflow_key}  (triggers: #{trigger_types_for(workflow)})" }

        workflows
      end

      def info(key)
        pack_loader.load!
        workflow_class = registry.fetch(key)

        stdout.puts "Workflow: #{key}"
        stdout.puts "  Class:    #{workflow_class}"
        stdout.puts "  Triggers:"
        workflow_class.triggers.each { |trigger| stdout.puts "    #{trigger.type}  key=#{trigger.unique_key}" }

        workflow_class
      end

      private

      attr_reader :pack_loader, :registry, :stdout

      def load_workflow(path)
        full_path = workflow_file_path(path)
        require full_path

        dir_name = File.basename(File.dirname(full_path))
        class_name = "Workflows::#{dir_name.camelize}"
        workflow = class_name.safe_constantize

        workflow ||= ObjectSpace.each_object(Class).find do |klass|
          klass < R3x::Workflow::Base &&
            klass.name.present? &&
            Object.const_source_location(klass.name)&.first == full_path
        end

        raise ArgumentError, "No workflow class found in #{path}" unless workflow

        workflow
      end

      def run_message(path, dry_run_explicit: false)
        mode_notes = []
        policy_dry_run = R3x::Policy.dry_run_for(:workflow)
        mode_notes << "dry run" if policy_dry_run
        mode_notes << "skip cache" if R3x::Policy.skip_cache?

        message = if mode_notes.any?
          "Running with #{mode_notes.join(" + ")}: #{path}"
        else
          "Running: #{path}"
        end

        message += " (--dry-run is redundant in this environment)" if dry_run_explicit && policy_dry_run

        message
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
        overrides["R3X_DRY_RUN"] = dry_run.to_s unless dry_run.nil?
        overrides["R3X_SKIP_CACHE"] = "true" if skip_cache

        originals = overrides.keys.each_with_object({}) { |key, memo| memo[key] = ENV[key] }

        overrides.each { |key, value| ENV[key] = value }

        yield
      ensure
        originals&.each do |key, value|
          value.nil? ? ENV.delete(key) : ENV[key] = value
        end
      end
    end
  end
end

# frozen_string_literal: true

module R3x
  module Workflow
    class Cli
      def initialize(stdout: $stdout, pack_loader: PackLoader, registry: Registry)
        @stdout = stdout
        @pack_loader = pack_loader
        @registry = registry
      end

      def run(path, dry_run: nil, skip_cache: false, wait: true)
        with_run_env(dry_run:, skip_cache:) do
          stdout.puts dry_run_message
          stdout.puts run_message(path)
          run_workflow(load_workflow(path), wait:)
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

      def run_workflow(workflow_class, wait:)
        workflow = workflow_class.new

        loop do
          return workflow.perform
        rescue ActiveJob::Continuation::Interrupt
          # Isolated Continuable steps interrupt so a queue adapter can persist progress
          # and resume the job later. The local CLI runs in-process, so it carries that
          # serialized continuation forward itself.
          max_resumptions = workflow.class.max_resumptions

          if max_resumptions && workflow.resumptions >= max_resumptions
            raise ActiveJob::Continuation::ResumeLimitError, "Job was resumed a maximum of #{max_resumptions} times"
          end

          sleep resume_delay_for(workflow) if wait
          workflow = workflow.class.deserialize(workflow.serialize).tap { it.resumptions += 1 }
        end
      end

      def resume_delay_for(workflow)
        resume_options = workflow.class.resume_options

        if resume_options[:wait_until]
          return [resume_options[:wait_until].to_f - Time.current.to_f, 0].max
        end

        return 0 unless resume_options[:wait]

        workflow.send(
          :determine_delay,
          seconds_or_duration_or_algorithm: resume_options[:wait],
          executions: workflow.resumptions + 1,
          jitter: 0,
        )
      end

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

      def run_message(path)
        mode_notes = []
        if R3x::Policy.default_dry_run_for
          mode_notes << (R3x::Env.fetch_boolean("R3X_DRY_RUN") ? "dry run" : "dry run by default")
        end
        mode_notes << "skip cache" if R3x::Policy.skip_cache?

        if mode_notes.any?
          "Running with #{mode_notes.join(" + ")}: #{path}"
        else
          "Running: #{path}"
        end
      end

      def dry_run_message
        overrides = dry_run_overrides
        real_overrides = overrides.select { |_, value| value == false }.keys

        if R3x::Env.fetch_boolean("R3X_DRY_RUN")
          message = "INFO: Global dry run enabled."
          message += " Ignored real-write overrides: #{real_overrides.join(", ")}." if real_overrides.any?
          message
        elsif R3x::Policy.default_dry_run_for
          if real_overrides.empty?
            "INFO: Default: dry run."
          else
            "WARN: Mixed mode. Default: dry run. Configured real-write overrides: #{real_overrides.join(", ")}."
          end
        else
          dry_overrides = overrides.select { |_, value| value }.keys
          message = "INFO: Default: real writes."
          message += " Configured dry-run overrides: #{dry_overrides.join(", ")}." if dry_overrides.any?
          message
        end
      end

      def dry_run_overrides
        ENV.keys.grep(/\AR3X_.+_DRY_RUN\z/).sort.to_h do |key|
          [key, R3x::Env.fetch_boolean(key)]
        end.compact
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
        # Apply CLI choices only for this run, then restore the original ENV.
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

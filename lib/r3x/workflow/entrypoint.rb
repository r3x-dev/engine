module R3x
  module Workflow
    module Entrypoint
      extend self

      def server_boot_action(rails_env:, solid_queue_in_puma: nil)
        return :load_and_schedule if rails_env == "development"
        return :load_and_schedule if enabled?(solid_queue_in_puma)

        :load
      end

      def jobs_boot_action(solid_queue_in_puma: nil)
        enabled?(solid_queue_in_puma) ? :load : :load_and_schedule
      end

      def boot_server!(rails_env:, solid_queue_in_puma: ENV["SOLID_QUEUE_IN_PUMA"], boot: Boot)
        dispatch_boot!(server_boot_action(rails_env:, solid_queue_in_puma:), boot:)
      end

      def start_jobs!(argv: ARGV, env: ENV, boot: Boot, cli: SolidQueue::Cli)
        dispatch_boot!(jobs_boot_action(solid_queue_in_puma: env["SOLID_QUEUE_IN_PUMA"]), boot:)
        cli.start(argv)
      end

      def start_jobs_worker!(argv: ARGV, env: ENV, boot: Boot, cli: SolidQueue::Cli)
        env["SOLID_QUEUE_CONFIG"] = "config/queue.worker.yml" if env["SOLID_QUEUE_CONFIG"].to_s.empty?
        env["SOLID_QUEUE_SKIP_RECURRING"] = "true" if env["SOLID_QUEUE_SKIP_RECURRING"].to_s.empty?

        boot.load!
        cli.start(argv)
      end

      def start_jobs_scheduler!(argv: ARGV, env: ENV, boot: Boot, cli: SolidQueue::Cli)
        env["SOLID_QUEUE_CONFIG"] = "config/queue.scheduler.yml" if env["SOLID_QUEUE_CONFIG"].to_s.empty?

        boot.load_and_schedule!
        cli.start(argv)
      end

      private

      def dispatch_boot!(action, boot:)
        case action
        when :load then boot.load!
        when :load_and_schedule then boot.load_and_schedule!
        else
          raise ArgumentError, "Unsupported boot action: #{action}"
        end
      end

      def enabled?(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end

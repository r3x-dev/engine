# frozen_string_literal: true

module R3x
  module Isolation
    class Bwrap < Base
      extend R3x::Concerns::Logger

      def self.run(workflow_class, context, trigger_key: nil, trigger_payload: nil, networking: false, **options)
        temp_dir = Dir.mktmpdir("r3x-sandbox-")
        socket_path = "#{temp_dir}/proxy.sock"
        state_file = "#{temp_dir}/workflow_state.json"
        env_path = Rails.root.join("config", "environment").to_s

        begin
          state = {
            workflow_key: context.execution.workflow_key,
            trigger_key: trigger_key
          }
          state[:trigger_payload] = trigger_payload if trigger_payload
          File.write(state_file, MultiJson.dump(state))

          proxy = nil
          proxy_thread = nil
          unless networking
            ready = Queue.new
            proxy = Proxy.new(socket_path)
            proxy_thread = Thread.new { proxy.start(ready) }
            ready.pop
          end

          logger.info("Starting sandbox for #{workflow_class.name} (networking: #{networking})")

          pid = fork do
            bwrap_args = build_bwrap_args(socket_path, state_file, networking: networking)
            log_file = "#{temp_dir}/child.log"

            exec({ "R3X_SANDBOX" => "1" },
                 "bwrap", *bwrap_args, "--",
                 RbConfig.ruby, "-e", runner_script(env_path),
                 out: log_file, err: log_file)
          end

          _, status = Process.wait2(pid)

          unless status.success?
            log_content = File.read("#{temp_dir}/child.log") rescue "No log file"
            raise "Sandboxed execution failed with exit code #{status.exitstatus}\nChild output:\n#{log_content}"
          end

          logger.info("Sandbox completed successfully")

        ensure
          proxy&.stop
          proxy_thread&.join(1) rescue nil
          FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
        end
      end

      def self.build_bwrap_args(socket_path, state_file, networking: false)
        ruby_path = RbConfig.ruby
        ruby_dir = File.dirname(ruby_path)
        parent_dir = File.dirname(ruby_dir)

        ruby_bind = if File.exist?(File.join(parent_dir, "lib"))
          [ "--ro-bind-try", parent_dir, parent_dir ]
        else
          [ "--ro-bind-try", ruby_dir, ruby_dir ]
        end

        args = [
          "--unshare-user",
          "--unshare-pid",
          "--unshare-ipc",
          "--unshare-uts",
          "--proc", "/proc",
          "--dev", "/dev",
          "--tmpfs", "/tmp",
          "--ro-bind", "/etc", "/etc",
          "--ro-bind", "/usr", "/usr",
          "--ro-bind", "/bin", "/bin",
          "--ro-bind", "/lib", "/lib",
          "--ro-bind-try", "/lib64", "/lib64",
          *ruby_bind,
          "--ro-bind", Rails.root.to_s, Rails.root.to_s,
          "--ro-bind-try", state_file, state_file,
          "--setenv", "R3X_STATE_FILE", state_file
        ]

        if networking
          args << "--share-net"
        else
          args << "--unshare-net"
          args << "--ro-bind-try" << socket_path << socket_path
          args << "--setenv" << "R3X_SANDBOX_SOCKET" << socket_path
        end

        args
      end

      def self.runner_script(env_path)
        <<~RUBY
          require '#{env_path}'
          R3x::Isolation::Bwrap::Runner.run(ENV.fetch('R3X_STATE_FILE'), env_path: '#{env_path}')
        RUBY
      end
    end
  end
end

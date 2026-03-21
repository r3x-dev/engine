module R3x
  module Isolation
    class Bwrap < Base
      def self.run(workflow_class, context, trigger_key: nil, trigger_payload: nil, networking: false, **options)
        temp_dir = Dir.mktmpdir("r3x-sandbox-")
        socket_path = "#{temp_dir}/proxy.sock"
        state_file = "#{temp_dir}/workflow_state.json"

        begin
          # Serialize workflow state for child
          state = {
            workflow_key: context.execution.workflow_key,
            workflow_class: workflow_class.name,
            trigger_key: trigger_key
          }
          state[:trigger_payload] = trigger_payload if trigger_payload
          File.write(state_file, MultiJson.dump(state))

          # Start proxy in background thread (only if networking is not allowed)
          proxy = nil
          proxy_thread = nil
          unless networking
            proxy = Proxy.new(socket_path)
            proxy_thread = Thread.new { proxy.start }

            # Wait for socket to be created (with timeout)
            100.times do
              break if File.exist?(socket_path)
              sleep 0.01
            end

            unless File.exist?(socket_path)
              raise "Proxy socket not created"
            end
          end

          logger.info("Starting sandbox for #{workflow_class.name} (networking: #{networking})")

          # Fork and execute workflow in bwrap
          pid = fork do
            # Build bwrap arguments
            bwrap_args = build_bwrap_args(socket_path, state_file, networking: networking)

            # Create log file for child output
            log_file = "#{temp_dir}/child.log"

            # Execute bwrap with current Ruby
            # Set R3X_SANDBOX=1 in child's environment only (not parent)
            exec({ "R3X_SANDBOX" => "1" },
                 "bwrap", *bwrap_args, "--",
                 RbConfig.ruby, "-e",
                 runner_script,
                 out: log_file, err: log_file)
          end

          # Parent waits for child
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

        rails_root = defined?(Rails) ? Rails.root.to_s : nil

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
          "--ro-bind-try", state_file, state_file,
          "--setenv", "R3X_STATE_FILE", state_file
        ]

        # Bind Rails root and gems for workflow loading
        if rails_root
          args << "--ro-bind" << rails_root << rails_root
          # Bind gem paths so Bundler can find gems
          Gem.path.each do |gem_path|
            args << "--ro-bind-try" << gem_path << gem_path
          end
        end

        # Add network isolation only if networking is not allowed
        if networking
          args << "--share-net"
        else
          args << "--unshare-net"
          args << "--ro-bind-try" << socket_path << socket_path if socket_path
          args << "--setenv" << "R3X_SANDBOX_SOCKET" << socket_path if socket_path
        end

        args
      end

      def self.runner_script
        env_path = defined?(Rails) ? Rails.root.join("config", "environment").to_s : "config/environment"

        <<~RUBY
          require 'json'

          state_file = ENV['R3X_STATE_FILE']
          unless state_file
            $stderr.puts "[Bwrap::Child] ERROR: Missing R3X_STATE_FILE"
            exit 1
          end

          state = JSON.parse(File.read(state_file))

          # Bootstrap Rails and the workflow registry
          require '#{env_path}'

          workflow_class = R3x::Workflow::Registry.fetch(state['workflow_key'])
          workflow_class.perform_now(state['trigger_key'], trigger_payload: state['trigger_payload'])
        RUBY
      end

      def self.logger
        if defined?(Rails)
          Rails.logger
        else
          Logger.new($stdout)
        end
      end
    end
  end
end

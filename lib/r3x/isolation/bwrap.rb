module R3x
  module Isolation
    class Bwrap < Base
      def self.run(workflow_class, context, networking: false, **options)
        temp_dir = Dir.mktmpdir("r3x-sandbox-")
        socket_path = "#{temp_dir}/proxy.sock"
        state_file = "#{temp_dir}/workflow_state.json"

        begin
          # Serialize workflow state for child
          File.write(state_file, JSON.dump({
            workflow_key: context.execution.workflow_key,
            workflow_class: workflow_class.name
          }))

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

          Rails.logger.info("[Bwrap] Starting sandbox for #{workflow_class.name} (networking: #{networking})")

          # Fork and execute workflow in bwrap
          pid = fork do
            # In child process - set up environment
            ENV["R3X_SANDBOX_SOCKET"] = socket_path if socket_path
            ENV["R3X_ISOLATED"] = "1"
            ENV["R3X_STATE_FILE"] = state_file
            ENV["R3X_WORKFLOW_CLASS"] = workflow_class.name

            # Build bwrap arguments
            bwrap_args = build_bwrap_args(socket_path, state_file, networking: networking)

            # Create log file for child output
            log_file = "#{temp_dir}/child.log"

            # Execute bwrap with current Ruby
            exec("bwrap", *bwrap_args, "--",
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

          Rails.logger.info("[Bwrap] Sandbox completed successfully")

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
          "--ro-bind-try", state_file, state_file,
          "--setenv", "R3X_ISOLATED", "1",
          "--setenv", "R3X_STATE_FILE", state_file
        ]

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
        <<~RUBY
          require 'json'
          require 'socket'

          state_file = ENV['R3X_STATE_FILE']
          workflow_class_name = ENV['R3X_WORKFLOW_CLASS']

          unless state_file && workflow_class_name
            puts "[Child] ERROR: Missing environment variables"
            exit 1
          end

          # Load state
          state = JSON.parse(File.read(state_file))

          # Create minimal context (just enough for workflow to run)
          ctx = OpenStruct.new(
            workflow_key: state['workflow_key'],
            workflow_class_name: workflow_class_name
          )

          puts "[Child] Running workflow \#{workflow_class_name}..."
          puts "[Child] Workflow key: \#{state['workflow_key']}"
          puts "[Child] Socket: \#{ENV['R3X_SANDBOX_SOCKET']}"
          puts "[Child] Isolated: \#{ENV['R3X_ISOLATED']}"

          # Test network isolation
          begin
            TCPSocket.new('google.com', 80)
            puts "[Child] ERROR: Network should be isolated!"
            exit 1
          rescue => e
            puts "[Child] OK: Network isolated (\#{e.class})"
          end

          # Test socket communication
          socket_path = ENV['R3X_SANDBOX_SOCKET']
          if socket_path && File.exist?(socket_path)
            socket = UNIXSocket.new(socket_path)
            socket.write("GET /test HTTP/1.1\r\nHost: example.com\r\n\r\n")
            response = socket.read
            puts "[Child] Proxy response: \#{response.lines.first.chomp}"
            socket.close
          end

          puts "[Child] Workflow \#{workflow_class_name} completed!"
        RUBY
      end
    end
  end
end

module R3x
  module Isolation
    # Forward declaration if Bwrap not yet loaded
    class Bwrap < Base; end unless defined?(Bwrap)

    class Bwrap
      class Proxy
        def initialize(socket_path)
          @socket_path = socket_path
          @server = nil
          @running = false
          @logger = defined?(Rails) ? Rails.logger : Logger.new(STDOUT)
        end

        def start
          @server = UNIXServer.new(@socket_path)
          @running = true
          @logger.info("[Bwrap::Proxy] Started on #{@socket_path}")

          loop do
            break unless @running

            begin
              client = @server.accept_nonblock(exception: false)
              next if client == :wait_readable

              Thread.new { handle_client(client) }
            rescue IOError
              break
            end
          end
        rescue IOError
          # Socket closed
        ensure
          @server&.close
        end

        def stop
          @running = false
          @server&.close rescue nil
        end

        private

        def handle_client(client)
          request = parse_request(client)
          return unless request

          response = forward_request(request)
          client.write(format_response(response))
        rescue => e
          @logger.error("[Bwrap::Proxy] Error: #{e.message}")
          client.write("HTTP/1.1 502 Bad Gateway\r\n\r\n")
        ensure
          client.close rescue nil
        end

        def parse_request(client)
          # Simple HTTP request parsing
          headers = {}
          method = nil
          path = nil

          loop do
            line = client.gets
            break unless line
            line = line.chomp

            if line.empty?
              # End of headers
              break
            elsif line =~ /^(GET|POST|PUT|DELETE|PATCH)\s+(\S+)\s+HTTP/
              method = $1
              path = $2
            elsif line =~ /^([^:]+):\s*(.+)$/
              headers[$1.downcase] = $2
            end
          end

          return nil unless method

          # Read body if present
          body = nil
          if headers["content-length"]
            body = client.read(headers["content-length"].to_i)
          end

          { method: method, path: path, headers: headers, body: body }
        end

        def forward_request(request)
          # For testing, just echo back
          host = request[:headers]["host"]

          @logger.info("[Bwrap::Proxy] #{request[:method]} #{request[:path]} -> #{host}")

          unless allowed_host?(host)
            return { status: 403, body: "Host not allowed: #{host}" }
          end

          # Simple test - just return success
          # Real implementation would forward via Faraday
          { status: 200, body: "{\"proxied\":true,\"host\":\"#{host}\"}" }
        rescue => e
          { status: 500, body: "Proxy error: #{e.message}" }
        end

        def format_response(response)
          body = response[:body].to_s
          "HTTP/1.1 #{response[:status]} OK\r\n" \
          "Content-Length: #{body.bytesize}\r\n" \
          "Content-Type: application/json\r\n" \
          "\r\n" \
          "#{body}"
        end

        def allowed_host?(host)
          # For testing, allow all hosts
          true
        end
      end
    end
  end
end

# frozen_string_literal: true

module R3x
  module Isolation
    # Forward declaration if Bwrap not yet loaded
    class Bwrap < Base; end unless defined?(Bwrap)

    class Bwrap
      class Proxy
        include R3x::Concerns::Logger

        STATUS_TEXTS = {
          200 => "OK",
          403 => "Forbidden",
          500 => "Internal Server Error",
          502 => "Bad Gateway"
        }.freeze

        def initialize(socket_path)
          @socket_path = socket_path
          @server = nil
          @running = false
        end

        def start(ready = nil)
          @server = UNIXServer.new(@socket_path)
          @running = true
          logger.info("Started on #{@socket_path}")
          ready << :ready if ready

          loop do
            break unless @running

            readable, = IO.select([ @server ], nil, nil, 0.5)
            next unless readable

            begin
              client = @server.accept
              Thread.new { handle_client(client) }
            rescue IOError
              break
            end
          end
        rescue => e
          ready << e if ready
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
          logger.error("Error: #{e.message}")
          client.write("HTTP/1.1 502 Bad Gateway\r\n\r\n")
        ensure
          client.close rescue nil
        end

        def parse_request(client)
          headers = {}
          method = nil
          path = nil

          loop do
            line = client.gets
            break unless line
            line = line.chomp

            if line.empty?
              break
            elsif line =~ /^(GET|POST|PUT|DELETE|PATCH)\s+(\S+)\s+HTTP/
              method = $1
              path = $2
            elsif line =~ /^([^:]+):\s*(.+)$/
              headers[$1.downcase] = $2
            end
          end

          return nil unless method

          body = nil
          if headers["content-length"]
            body = client.read(headers["content-length"].to_i)
          end

          { method: method, path: path, headers: headers, body: body }
        end

        def forward_request(request)
          host = request[:headers]["host"]
          logger.info("#{request[:method]} #{request[:path]} -> #{host}")

          unless allowed_host?(host)
            return { status: 403, body: "Host not allowed: #{host}" }
          end

          # Stub — real implementation would forward via Faraday
          { status: 200, body: "{\"proxied\":true,\"host\":\"#{host}\"}" }
        rescue => e
          { status: 500, body: "Proxy error: #{e.message}" }
        end

        def format_response(response)
          status = response[:status]
          body = response[:body].to_s
          status_text = STATUS_TEXTS[status] || "Unknown"

          "HTTP/1.1 #{status} #{status_text}\r\n" \
          "Content-Length: #{body.bytesize}\r\n" \
          "Content-Type: application/json\r\n" \
          "\r\n" \
          "#{body}"
        end

        def allowed_host?(host)
          # Stub — real implementation would check against allowlist
          true
        end
      end
    end
  end
end

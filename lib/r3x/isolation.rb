module R3x
  module Isolation
    DEFAULT_MODE = "bwrap".freeze

    def self.for(mode: nil)
      # Skip isolation when already running inside a sandbox
      return None if ENV["R3X_SANDBOX"]

      mode ||= ENV.fetch("R3X_ISOLATION_MODE", DEFAULT_MODE)
      mode = mode.to_s.strip
      mode = DEFAULT_MODE if mode.empty?

      # In test environment, default to "none" for simplicity
      # unless explicitly overridden via R3X_ISOLATION_MODE
      if defined?(Rails) && Rails.env.test? && mode == DEFAULT_MODE && !ENV.key?("R3X_ISOLATION_MODE")
        mode = "none"
      end

      # Check if bwrap is available when explicitly requested
      if mode == "bwrap" && !bwrap_available?
        raise "Bubblewrap (bwrap) is not installed but R3X_ISOLATION_MODE=bwrap was requested. " \
              "Please install bwrap or set R3X_ISOLATION_MODE=none"
      end

      case mode
      when "none"
        None
      when "bwrap"
        Bwrap
      else
        raise ArgumentError, "Unknown isolation mode: #{mode}"
      end
    end

    def self.bwrap_available?
      system("which bwrap > /dev/null 2>&1")
    end
  end
end

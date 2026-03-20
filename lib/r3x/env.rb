module R3x
  module Env
    INTERNAL_PREFIX = "R3X_"

    def self.logger
      Rails.logger.tagged(self.name)
    end

    def self.fetch(key)
      ENV[key].presence
    end

    def self.fetch!(key)
      fetch(key) || raise(ArgumentError, "Missing #{key}")
    end

    def self.present?(key)
      ENV[key].present?
    end

    def self.secure_fetch(key, prefix:)
      case prefix
      when String
        unless key.start_with?(prefix)
          raise ArgumentError, "Key '#{key}' must start with '#{prefix}'"
        end
      when Regexp
        unless key.match?(prefix)
          raise ArgumentError, "Key '#{key}' must match #{prefix}"
        end
      else
        raise ArgumentError, "prefix must be a String or Regexp, got #{prefix.class}"
      end

      fetch!(key)
    end

    def self.load_from_vault(path)
      unless R3x::Client::HashiCorpVault.configured?
        logger.info "VAULT_ADDR or VAULT_TOKEN not set - skipping Vault"
        return {}
      end

      logger.info "Loading secrets from Vault: #{path}"
      secrets = R3x::Client::HashiCorpVault.read(path)
      loaded = {}

      secrets.each do |key, value|
        next if key.start_with?(INTERNAL_PREFIX)
        ENV[key] = value.to_s
        loaded[key] = true
      end

      logger.info "Loaded #{loaded.size} secrets from Vault"
      loaded
    rescue StandardError => e
      logger.warn "Vault error: #{e.message}"
      {}
    end
  end
end

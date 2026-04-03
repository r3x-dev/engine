module R3x
  module Env
    INTERNAL_PREFIX = "R3X_"

    def self.logger
      Rails.logger.tagged(name)
    end

    def self.fetch(key)
      ENV[key].presence
    end

    def self.fetch!(key)
      fetch(key) || raise(ArgumentError, "Missing #{key}")
    end

    # Intentionally not using ActiveModel::Type::Boolean.new.cast — it silently
    # returns true for any unrecognized value instead of raising, which would
    # silently accept typos in env vars (e.g. "fasle" → true). We want to fail
    # fast with a clear error for invalid input.
    def self.fetch_boolean(key)
      value = fetch(key)
      return if value.nil?

      case value.to_s.downcase
      when "1", "true", "yes", "on"
        true
      when "0", "false", "no", "off"
        false
      else
        raise ArgumentError, "Invalid boolean for #{key}: #{value.inspect}"
      end
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
        logger.info "R3X_VAULT_ADDR or R3X_VAULT_TOKEN not set - skipping Vault"
        return {}
      end

      logger.info "Loading secrets from Vault: #{path}"
      secrets = R3x::Client::HashiCorpVault.read(path)
      loaded = {}

      secrets.each do |key, value|
        if key.start_with?(INTERNAL_PREFIX)
          raise "Vault secret key '#{key}' starts with reserved prefix '#{INTERNAL_PREFIX}'"
        end
        ENV[key] = value.to_s
        loaded[key] = true
      end

      logger.info "Loaded #{loaded.size} secrets from Vault"
      loaded
    rescue RuntimeError
      raise
    rescue => e
      logger.warn "Vault error: #{e.message}"
      {}
    end
  end
end

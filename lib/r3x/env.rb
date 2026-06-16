module R3x
  module Env
    # R3x::Env is loaded during early boot (e.g. config/runtime_profile.rb),
    # before Rails autoloading is available. It therefore cannot depend on
    # R3x::Concerns::Logger, which lives under app/lib/. Vault logging uses
    # Rails.logger directly because it is only called once Rails is booted.
    INTERNAL_PREFIX = "R3X_"

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
      raise ArgumentError, "Missing env key for #{prefix}" if key.blank?

      case prefix
      when String
        unless key == prefix.delete_suffix("_") || key.start_with?(prefix)
          raise ArgumentError, "Key '#{key}' must be '#{prefix.delete_suffix("_")}' or start with '#{prefix}'"
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
      return {} if path.blank?

      unless R3x::Env.present?("R3X_VAULT_ADDR")
        Rails.logger.info("Vault auth not configured - skipping Vault")
        return {}
      end

      R3x::Client::HashiCorpVault.validate_auth_configuration!

      Rails.logger.info("Loading secrets from Vault: #{path}")
      secrets = R3x::Client::HashiCorpVault.read(path)
      loaded = {}

      secrets.each do |key, value|
        if key.start_with?(INTERNAL_PREFIX)
          raise "Vault secret key '#{key}' starts with reserved prefix '#{INTERNAL_PREFIX}'"
        end

        ENV[key] = value.to_s
        loaded[key] = true
      end

      Rails.logger.info("Loaded #{loaded.size} secrets from Vault")
      loaded
    end
  end
end

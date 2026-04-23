module R3x
  module RuntimeProfile
    extend self

    DEFAULT_PROFILE = "web"
    HEADLESS_PROFILES = %w[jobs workflow_cli].freeze
    SUPPORTED_PROFILES = [ DEFAULT_PROFILE, *HEADLESS_PROFILES ].freeze

    def current(env = ENV)
      profile = env.fetch("R3X_RUNTIME_PROFILE", "").to_s
      profile = DEFAULT_PROFILE if profile.empty?

      case profile
      when *SUPPORTED_PROFILES
        profile
      else
        raise ArgumentError, "Unsupported R3X_RUNTIME_PROFILE: #{profile}"
      end
    end

    def jobs?(env = ENV)
      current(env) == "jobs"
    end

    def workflow_cli?(env = ENV)
      current(env) == "workflow_cli"
    end

    def headless?(env = ENV)
      HEADLESS_PROFILES.include?(current(env))
    end

    def bundler_groups(env = ENV)
      headless?(env) ? [] : [ :web ]
    end
  end
end

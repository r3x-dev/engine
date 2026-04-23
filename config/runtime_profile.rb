module R3x
  module RuntimeProfile
    extend self

    DEFAULT_PROFILE = "web"
    HEADLESS_PROFILES = %w[jobs workflow_cli].freeze
    SUPPORTED_PROFILES = [ DEFAULT_PROFILE, *HEADLESS_PROFILES ].freeze

    def current
      @current ||= begin
        profile = ENV.fetch("R3X_RUNTIME_PROFILE", "").to_s
        profile = DEFAULT_PROFILE if profile.empty?

        case profile
        when *SUPPORTED_PROFILES
          profile
        else
          raise ArgumentError, "Unsupported R3X_RUNTIME_PROFILE: #{profile}"
        end
      end
    end

    def jobs?
      current == "jobs"
    end

    def workflow_cli?
      current == "workflow_cli"
    end

    def headless?
      HEADLESS_PROFILES.include?(current)
    end

    def bundler_groups
      headless? ? [] : [ :web ]
    end
  end
end

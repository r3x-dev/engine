require_relative "boot"
require_relative "log_formatter"
require_relative "runtime_profile"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"

unless R3x::RuntimeProfile.headless?
  require "action_controller/railtie"
  require "action_view/railtie"
  require "rails/test_unit/railtie"
end

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups(*R3x::RuntimeProfile.bundler_groups))

module R3x
  class Application < Rails::Application
    HEADLESS_AUTOLOAD_IGNORES = [
      Rails.root.join("app/controllers"),
      Rails.root.join("app/helpers"),
      Rails.root.join("app/lib/r3x/dashboard")
    ].freeze
    JOBS_ONLY_AUTOLOAD_IGNORES = [
      Rails.root.join("lib/r3x/workflow/cli.rb")
    ].freeze

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that
    # do not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])
    config.autoload_paths << Rails.root.join("app/lib")
    config.eager_load_paths << Rails.root.join("app/lib")

    if R3x::RuntimeProfile.headless?
      # Headless entrypoints keep the Rails application boot, but they do not
      # serve the dashboard or health endpoint. Remove app route files before
      # Rails wires them into the routes reloader so headless entrypoints never
      # load config/routes*.rb.
      paths["config/routes.rb"] = []
      paths["config/routes"] = []

      initializer "r3x.runtime_profile.ignore_web_paths" do
        Rails.autoloaders.main.ignore(*HEADLESS_AUTOLOAD_IGNORES)
        Rails.autoloaders.once.ignore(*HEADLESS_AUTOLOAD_IGNORES)
      end

      if R3x::RuntimeProfile.jobs?
        initializer "r3x.runtime_profile.ignore_jobs_only_paths" do
          Rails.autoloaders.main.ignore(*JOBS_ONLY_AUTOLOAD_IGNORES)
          Rails.autoloaders.once.ignore(*JOBS_ONLY_AUTOLOAD_IGNORES)
        end
      end

      # Rails still eager-loads framework controllers such as Rails::HealthController
      # during boot. Keep include_all_helpers off so ActionController::Base does not
      # scan app/helpers and pull web-only constants back into headless runtimes.
      initializer "r3x.runtime_profile.disable_include_all_helpers" do
        require "action_controller"
        ActionController::Base.include_all_helpers = false
      end
    else
      config.api_only = true
      config.mission_control.jobs.base_controller_class = "R3x::WebController"
      server { R3x::Workflow::Entrypoint.boot_server!(rails_env: Rails.env) }
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
  end
end

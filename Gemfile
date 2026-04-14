source "https://rubygems.org"
ruby File.read(File.expand_path(".ruby-version", __dir__)).strip

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use PostgreSQL as an alternative database adapter
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# HTTP client
gem "faraday"
gem "faraday-multipart"

# Json
gem "multi_json"

# HTML/XML parsing
gem "nokogiri"

# LLM integration
gem "ruby_llm", require: false
gem "ruby_llm-schema", require: false

# Google Translate API
gem "google-cloud-translate", require: false

# Google OAuth and API integration
gem "googleauth"
gem "google-apis-calendar_v3", require: false
gem "google-apis-gmail_v1", require: false
gem "google-apis-sheets_v4", require: false
gem "mail"

# Use the database-backed adapters for Rails.cache and Active Job
gem "solid_cache"
gem "solid_queue"

# CLI tools
gem "highline", require: false

# Active Job dashboard (requires propshaft for API-only apps)
gem "mission_control-jobs"
gem "propshaft"
gem "heroicon"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "rubocop-minitest", require: false
  gem "rubocop-thread_safety", "~> 0.7.3", require: false

  # Auto-load environment variables from .env file
  gem "dotenv-rails", require: false
end

group :test do
  gem "webmock"
end

gem "retryable", "~> 3.0"

gem "amazing_print", "~> 2.0", require: false
